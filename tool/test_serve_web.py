import threading
import unittest
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from unittest.mock import patch, MagicMock
from serve_web import PreviewHandler


class QuietHandler(PreviewHandler):
    def log_message(self, *_):
        pass


class ProxyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), QuietHandler)
        cls.worker = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.worker.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.worker.join()

    def request(self, method, headers=None, body=None):
        conn = HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        conn.request(method, '/api/reminders/1?test=1', body=body,
                     headers={'Host': '127.0.0.1:8765', **(headers or {})})
        response = conn.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        conn.close()
        return result

    @patch('serve_web.HTTPSConnection')
    def test_preserves_methods_auth_json_and_session_without_forwarding_cookies(self, upstream):
        response = MagicMock(status=200)
        response.read.return_value = b'{"data":{}}'
        response.getheader.side_effect = lambda key: {'Content-Type': 'application/json', 'X-Session-Token': 'renewed-test'}.get(key)
        upstream.return_value.getresponse.return_value = response
        for method in ('GET', 'POST', 'PATCH', 'DELETE'):
            status, headers, data = self.request(method, {
                'Origin': 'http://127.0.0.1:8765', 'Authorization': 'Bearer test-only',
                'Content-Type': 'application/json', 'Cookie': 'must-not-forward=1',
            }, b'{"active":false}')
            self.assertEqual(status, 200)
            self.assertEqual(headers['X-Session-Token'], 'renewed-test')
            self.assertEqual(data, b'{"data":{}}')
            upstream.assert_called_with('bus.su7.space', timeout=20)
            upstream.return_value.request.assert_called_with(method, '/api/reminders/1?test=1',
                body=b'{"active":false}', headers={'Accept': 'application/json', 'Authorization': 'Bearer test-only', 'Content-Type': 'application/json'})

    @patch('serve_web.HTTPSConnection')
    def test_untrusted_requests_are_rejected_without_upstream(self, upstream):
        for headers, expected in [
            ({'Origin': 'https://untrusted.example'}, 403),
            ({'Host': 'untrusted.example'}, 403),
            ({'Content-Length': '1048577'}, 413),
            ({'Content-Type': 'text/plain'}, 415),
            ({'Transfer-Encoding': 'chunked'}, 400),
        ]:
            status, _, _ = self.request('PATCH', headers, b'{}')
            self.assertEqual(status, expected)
        upstream.assert_not_called()

    @patch('serve_web.HTTPSConnection')
    def test_auth_errors_and_network_failures_remain_distinct(self, upstream):
        response = MagicMock(status=401)
        response.read.return_value = b'{"error":{"message":"login required"}}'
        response.getheader.return_value = None
        upstream.return_value.getresponse.return_value = response
        self.assertEqual(self.request('PATCH')[0], 401)
        upstream.return_value.request.side_effect = OSError('offline')
        status, _, data = self.request('PATCH')
        self.assertEqual(status, 502)
        self.assertIn(b'error', data)


if __name__ == '__main__':
    unittest.main()
