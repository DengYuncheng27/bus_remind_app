"""Package tested Flutter Web artifacts; deploy only the authorized client component."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import urllib.request

PARTS = ('client.tar.gz',)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(data)
    return digest.hexdigest()


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def package(directory, revision):
    if not re.fullmatch('[0-9a-f]{40}', revision) or run('git', 'rev-parse', 'HEAD') != revision:
        raise ValueError('Package must use the checked-out CI commit')
    if run('git', 'status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError('Tracked source files changed during the build')
    if run('git', 'rev-parse', 'refs/heads/main') != revision:
        raise RuntimeError('Only the exact main checkout can be packaged for production')
    directory.mkdir(parents=True, exist_ok=True)
    folder = Path('build/web')
    for entry in ('index.html', 'flutter_bootstrap.js', 'sw.js', 'web-push.js', 'download.html'):
        if not (folder / entry).is_file():
            raise RuntimeError('Missing required Web artifact: ' + entry)
    with tarfile.open(directory / 'client.tar.gz', 'w:gz') as archive:
        for path in sorted(folder.rglob('*')):
            if path.is_symlink():
                raise RuntimeError('Build artifacts must not contain symlinks')
            if path.is_file():
                archive.add(path, arcname='client/' + path.relative_to(folder).as_posix())
    manifest = {'revision': revision, 'parts': {
        name: {'size': (directory / name).stat().st_size, 'sha256': sha256(directory / name)} for name in PARTS}}
    (directory / 'artifact.json').write_text(json.dumps(manifest, indent=2) + '\n')


def verify_artifacts(directory, revision):
    manifest = json.loads((directory / 'artifact.json').read_text())
    if manifest.get('revision') != revision or set(manifest.get('parts', {})) != set(PARTS):
        raise ValueError('Artifact provenance does not match this CI commit')
    for name in PARTS:
        if manifest['parts'][name] != {'size': (directory / name).stat().st_size, 'sha256': sha256(directory / name)}:
            raise ValueError('Artifact checksum mismatch: ' + name)
    return manifest


def latest_main(repository):
    request = urllib.request.Request(f'https://api.github.com/repos/{repository}/git/ref/heads/main', headers={
        'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json',
        'User-Agent': 'BusReminder-CD'})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)['object']['sha']


def check_public_health():
    # Cloudflare Browser Integrity Check rejects Python's generic default UA (1010).
    request = urllib.request.Request('https://bus.su7.space/health', headers={
        'User-Agent': 'BusReminder-CD/1.0', 'Accept': 'application/json'})
    with urllib.request.urlopen(request, timeout=20) as response:
        if json.load(response).get('status') != 'ok':
            raise RuntimeError('Public health check failed after deployment')


def deploy(directory, revision):
    if os.environ.get('GITHUB_EVENT_NAME') != 'push' or os.environ.get('GITHUB_REF') != 'refs/heads/main':
        raise RuntimeError('Production deployment requires a main push workflow')
    manifest = verify_artifacts(directory, revision)
    if latest_main(os.environ['GITHUB_REPOSITORY']) != revision:
        print('A newer main commit exists; skipping this superseded deployment.')
        return
    host, user, port = (os.environ['CD_SSH_HOST'], os.environ['CD_SSH_USER'], os.environ['CD_SSH_PORT'])
    if not re.fullmatch('[a-zA-Z0-9.-]+', host) or not re.fullmatch('[a-z_][a-z0-9_-]*', user) or not port.isdigit():
        raise ValueError('Invalid SSH connection settings')
    with tempfile.TemporaryDirectory(prefix='busreminder-ssh-') as temporary:
        key, hosts = Path(temporary) / 'key', Path(temporary) / 'known_hosts'
        for path, value in ((key, os.environ['CD_SSH_PRIVATE_KEY']), (hosts, os.environ['CD_SSH_KNOWN_HOSTS'])):
            with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
                stream.write(value.rstrip() + '\n')
        ssh = ['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes',
               '-o', 'UserKnownHostsFile=' + str(hosts), '-o', 'ConnectTimeout=15',
               '-o', 'ServerAliveInterval=20', '-i', str(key), '-p', port, user + '@' + host]
        state = json.loads(run(*ssh, 'status'))
        # A main release may advance the deployed source, never silently revert it.
        subprocess.run(['git', 'merge-base', '--is-ancestor', state['clientRevision'], revision], check=True)
        request = {'revision': revision, 'expectedRevision': state['backendRevision'],
                   'expectedRelease': state['backendPath'], 'parts': manifest['parts']}
        # Recheck after obtaining the deployment baseline, before handing over artifacts.
        if latest_main(os.environ['GITHUB_REPOSITORY']) != revision:
            print('Main advanced while preparing deployment; skipping.')
            return
        with tempfile.TemporaryFile() as payload, tempfile.TemporaryFile() as response:
            payload.write(json.dumps(request).encode() + b'\n')
            for name in PARTS:
                with (directory / name).open('rb') as source:
                    for data in iter(lambda: source.read(1024 * 1024), b''):
                        payload.write(data)
            payload.seek(0)
            result = subprocess.run(ssh + ['deploy'], stdin=payload, stdout=response, stderr=subprocess.STDOUT)
            response.seek(0)
            output = response.read().decode('utf-8', 'replace')
            print(output)
            result.check_returncode()
        records = [json.loads(line) for line in output.splitlines() if line.startswith('{')]
        if not records or records[-1].get('clientRevision') != revision:
            raise RuntimeError('Server did not confirm the selected revision')
        check_public_health()
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write('Deployed Flutter Web `' + revision + '`; preserved the recorded live backend/admin. Android was not released.\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('package', 'deploy'))
    parser.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    revision = os.environ['GITHUB_SHA']
    (package if args.command == 'package' else deploy)(args.directory, revision)
