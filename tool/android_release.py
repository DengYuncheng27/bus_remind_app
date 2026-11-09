"""Validate and package an Android release; never uploads files or reads signing secrets."""
import argparse
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
    parser.add_argument('command', choices=['version', 'package', 'check-upgrade'])
    parser.add_argument('--tag', required=True)
    parser.add_argument('--apk', type=Path, default=ROOT / 'build/app/outputs/flutter-apk/app-release.apk')
    parser.add_argument('--build-tools', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/release')
    parser.add_argument('--previous', type=Path)
    args = parser.parse_args()
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
