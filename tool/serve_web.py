"""Serve the local Flutter build without stale application caches.

Versioned paths bypass legacy Flutter service-worker resource keys while
keeping the same origin (and therefore the user's existing login).
Run from the repository root: python tool/serve_web.py
"""
from hashlib import sha256
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import re
import json
from http.client import HTTPSConnection, HTTPException

BUILD = Path(__file__).resolve().parents[1] / 'build' / 'web'
_signature = None
_version = None


def version():
    global _signature, _version
    files = [BUILD / name for name in ('index.html', 'flutter_bootstrap.js', 'main.dart.js')]
    signature = tuple((file.stat().st_mtime_ns, file.stat().st_size) for file in files)
    if signature != _signature:
        digest = sha256()
        for file in files:
            digest.update(file.read_bytes())
        _version = digest.hexdigest()[:12]
        _signature = signature
    return _version


class PreviewHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(BUILD), **kwargs)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, max-age=0')
        super().end_headers()

    def translate_path(self, path):
        path = urlsplit(path).path
        path = re.sub(r'^/preview/[a-f0-9]{12}/', '/', path)
        path = re.sub(r'^/app/', '/', path)
        return super().translate_path(path)

    def send_text(self, text, mime):
        body = text.encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', mime + '; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)

    def send_head(self):
        # A local preview must never return a cached build via a 304 response.
        if 'If-Modified-Since' in self.headers:
            del self.headers['If-Modified-Since']
        return super().send_head()

    def serve(self):
        path = urlsplit(self.path).path
        if path.startswith('/api/'):
            self.proxy_api()
            return
        if self.command not in ('GET', 'HEAD'):
            self.send_error(405)
            return
        prefix = f'/preview/{version()}/'
        if path == '/':
            self.send_text((BUILD / 'download.html').read_text(encoding='utf-8'), 'text/html')
            return
        if path in ('/download.html', '/index.html', '/app'):
            self.send_response(302)
            destination = '/app/' if path == '/app' else '/'
            query = urlsplit(self.path).query
            self.send_header('Location', destination + ('?' + query if query else ''))
            self.end_headers()
            return
        match = re.fullmatch(r'/preview/([a-f0-9]{12})/(.*)', path)
        if path in ('/app/', '/app/index.html') or (match and match[2] in ('', 'index.html')):
            if match and match[1] != version():
                self.send_response(302)
                self.send_header('Location', prefix)
                self.end_headers()
                return
            html = (BUILD / 'index.html').read_text(encoding='utf-8')
            base = prefix if match else '/app/'
            html = re.sub(r'<base href="[^"]*"', f'<base href="{base}"', html)
            # Retire only the old Flutter worker for this app; keep all account
            # storage and cookies. Other workers on this origin are untouched.
            cleanup = '''<script>
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(registrations => {
    for (const registration of registrations) {
      const worker = registration.active || registration.waiting || registration.installing;
      if (worker && new URL(worker.scriptURL).pathname === '/flutter_service_worker.js') {
        registration.unregister();
      }
    }
  }).catch(() => {});
}
</script>'''
            self.send_text(html.replace('<body>', '<body>' + cleanup), 'text/html')
            return
        if path.endswith('/flutter_bootstrap.js'):
            bootstrap = (BUILD / 'flutter_bootstrap.js').read_text(encoding='utf-8')
            # The preview needs no offline worker. Keep the generated loader
            # and build config, changing only its final startup invocation.
            bootstrap = bootstrap.rsplit('_flutter.loader.load(', 1)[0] + '_flutter.loader.load();\n'
            self.send_text(bootstrap, 'text/javascript')
            return
        if self.command == 'HEAD':
            super().do_HEAD()
        else:
            super().do_GET()

    do_GET = serve
    do_HEAD = serve
    do_POST = serve
    do_PATCH = serve
    do_DELETE = serve

    def proxy_api(self):
        # Fixed HTTPS destination; never accept arbitrary URLs or follow redirects.
        # Authentication remains enforced by the real API using the caller's JWT.
        if (self.headers.get('Host') != '127.0.0.1:8765' or
                self.headers.get('Origin', 'http://127.0.0.1:8765') != 'http://127.0.0.1:8765'):
            self.send_error(403)
            return
        if self.headers.get('Transfer-Encoding'):
            self.send_error(400)
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            self.send_error(400)
            return
        if not 0 <= size <= 1_048_576:
            self.send_error(413)
            return
        if size and self.headers.get_content_type() != 'application/json':
            self.send_error(415)
            return
        headers = {'Accept': 'application/json'}
        for key in ('Authorization', 'Content-Type'):
            if self.headers.get(key):
                headers[key] = self.headers[key]
        body = self.rfile.read(size) if size else None
        upstream = HTTPSConnection('bus.su7.space', timeout=20)
        try:
            upstream.request(self.command, self.path, body=body, headers=headers)
            response = upstream.getresponse()
            data = response.read()
            status = response.status
            response_headers = {key: response.getheader(key) for key in
                                ('Content-Type', 'X-Session-Token', 'Retry-After')}
        except (OSError, HTTPException):
            data = json.dumps({'error': {'message': '公交服务暂时无法连接，请稍后重试'}}).encode()
            status = 502
            response_headers = {'Content-Type': 'application/json'}
        finally:
            upstream.close()
        self.send_response(status)
        for key, value in response_headers.items():
            if value:
                self.send_header(key, value)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(data)


if __name__ == '__main__':
    print(f'Preview: http://127.0.0.1:8765/preview/{version()}/', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 8765), PreviewHandler).serve_forever()
