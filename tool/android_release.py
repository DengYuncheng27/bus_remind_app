"""Validate and package an Android release; never uploads files or reads signing secrets."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = 'DengYuncheng27/bus_remind_app'
ASSET = 'xiabanwang-android-arm64.apk'
PACKAGE = 'space.su7.xiabanwang'


def version_info(pubspec, tag):
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$', pubspec, re.M)
    if not match:
        raise ValueError('pubspec.yaml must contain version: major.minor.patch+buildNumber')
    version, build = match.groups()
    if tag != 'v' + version:
        raise ValueError('Release tag must match pubspec.yaml: v' + version)
    return {'version': version, 'versionCode': int(build), 'tag': tag}


def validate_apk(info, badging, certificates, expected_signer, members):
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
    if not package or package.groups() != (PACKAGE, str(info['versionCode']), info['version']):
        raise ValueError('APK application ID/version does not match this release')
    signers = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})$', certificates, re.M)
    if [s.lower() for s in signers] != [expected_signer.strip().lower()]:
        raise ValueError('APK signer differs from the existing production certificate')
    flutter_abis = {name.split('/')[1] for name in members if re.fullmatch(r'lib/[^/]+/libflutter\.so', name)}
    if flutter_abis != {'arm64-v8a'}:
        raise ValueError('The ARM64 download must contain exactly the ARM64 Flutter runtime')


def check_upgrade(current, previous):
    if (current['versionCode'] <= previous['versionCode'] or
            tuple(map(int, current['version'].split('.'))) <= tuple(map(int, previous['version'].split('.')))):
        raise ValueError('Both version and versionCode must increase; do not replace published APKs')


def validate_patch_files(files):
    """Only patch a released base whose native dependencies and assets are unchanged."""
    blocked = [name for name in files if name.startswith(('android/', 'assets/')) or
               name in ('pubspec.yaml', 'pubspec.lock', 'shorebird.yaml')]
    if blocked:
        raise ValueError('Publish a full APK for native/dependency/asset changes: ' + ', '.join(blocked))


def validate_shorebird_config(compiled, source):
    # The pinned SDK emits flat scalar YAML and injects patch_public_key.
    # Compare runtime settings, not comments/formatting or the injected key.
    def fields(text):
        values = {}
        for line in text.splitlines():
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            match = re.fullmatch(r'([a-z_]+):\s*(\S.*?)\s*', line)
            if not match or match[1] in values:
                raise ValueError('Unexpected or duplicate Shorebird configuration field')
            values[match[1]] = match[2].strip('\"\'')
        return values
    actual, expected = fields(compiled), fields(source)
    public_key = actual.pop('patch_public_key', '')
    if actual != expected or actual.get('auto_update') != 'false':
        raise ValueError('APK Shorebird runtime settings do not match this release')
    try:
        key = base64.b64decode(public_key, validate=True)
    except ValueError as error:
        raise ValueError('APK has an invalid patch verification key') from error
    if len(key) < 32:
        raise ValueError('APK is missing a patch verification key')


def check_patch(release_version):
    if not re.fullmatch(r'\d+\.\d+\.\d+\+[1-9]\d*', release_version or ''):
        raise ValueError('Use an explicit release version, e.g. 0.3.7+10; never latest')
    tag = 'v' + release_version.split('+')[0]
    info = version_info((ROOT / 'pubspec.yaml').read_text(encoding='utf-8'), tag)
    if f'{info["version"]}+{info["versionCode"]}' != release_version:
        raise ValueError('Patch source must keep the base version and build number')
    base_spec = run('git', '-C', str(ROOT), 'show', f'{tag}:pubspec.yaml')
    if version_info(base_spec, tag) != info:
        raise ValueError('The target tag does not match the base release')
    run('git', '-C', str(ROOT), 'merge-base', '--is-ancestor', tag, 'HEAD')
    files = run('git', '-C', str(ROOT), 'diff', '--name-only', tag, 'HEAD').splitlines()
    validate_patch_files(files)


def sdk_tool(name, build_tools):
    suffix = ('.bat' if name == 'apksigner' else '.exe') if os.name == 'nt' else ''
    return str(Path(build_tools) / (name + suffix))


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, encoding='utf-8').stdout


def package_release(info, apk, build_tools, output):
    # apksigner must return success, not just print a certificate.
    certificates = run(sdk_tool('apksigner', build_tools), 'verify', '--print-certs', str(apk))
    badging = run(sdk_tool('aapt', build_tools), 'dump', 'badging', str(apk))
    signer = (ROOT / 'tool/android-signing.sha256').read_text().strip()
    with zipfile.ZipFile(apk) as archive:
        validate_apk(info, badging, certificates, signer, archive.namelist())
        config = archive.read('assets/flutter_assets/shorebird.yaml').decode('utf-8')
        validate_shorebird_config(config, (ROOT / 'shorebird.yaml').read_text(encoding='utf-8'))
        if b'shorebird_check_for_downloadable_update' not in archive.read('lib/arm64-v8a/libflutter.so'):
            raise ValueError('APK does not contain the Shorebird update engine')
    output.mkdir(parents=True, exist_ok=True)
    target = output / ASSET
    shutil.copyfile(apk, target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    metadata = dict(info, applicationId=PACKAGE, abi='arm64-v8a', sha256=digest,
                    size=target.stat().st_size, signingCertificateSha256=signer,
                    sourceRevision=run('git', '-C', str(ROOT), 'rev-parse', 'HEAD').strip(),
                    url=f'https://github.com/{REPOSITORY}/releases/download/{info["tag"]}/{ASSET}')
    (output / 'android-release.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    (output / 'SHA256SUMS').write_text(f'{digest}  {ASSET}\n', encoding='utf-8')
    print(json.dumps(metadata))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['version', 'package', 'check-upgrade', 'patch'])
    parser.add_argument('--tag')
    parser.add_argument('--release-version')
    parser.add_argument('--apk', type=Path, default=ROOT / 'build/app/outputs/flutter-apk/app-release.apk')
    parser.add_argument('--build-tools', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/release')
    parser.add_argument('--previous', type=Path)
    args = parser.parse_args()
    if args.command == 'patch':
        check_patch(args.release_version)
        return
    info = version_info((ROOT / 'pubspec.yaml').read_text(encoding='utf-8'), args.tag)
    if args.command == 'version':
        print(json.dumps(info))
    elif args.command == 'check-upgrade':
        if not args.previous:
            parser.error('--previous is required')
        check_upgrade(info, json.loads(args.previous.read_text(encoding='utf-8')))
    else:
        if not args.build_tools:
            parser.error('--build-tools is required')
        package_release(info, args.apk, args.build_tools, args.output)


if __name__ == '__main__':
    main()
