import unittest

from android_release import check_upgrade, validate_apk, version_info


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.info = version_info('name: xiabanwang\nversion: 0.3.2+5\n', 'v0.3.2')
        self.badging = "package: name='space.su7.xiabanwang' versionCode='5' versionName='0.3.2'\n"
        self.signer = 'a' * 64
        self.certificates = 'Signer #1 certificate SHA-256 digest: ' + self.signer + '\n'
        self.members = ['lib/arm64-v8a/libflutter.so', 'lib/armeabi-v7a/libjcore.so']

    def validate(self, **changes):
        values = dict(info=self.info, badging=self.badging, certificates=self.certificates,
                      expected_signer=self.signer, members=self.members)
        validate_apk(**dict(values, **changes))

    def test_tag_must_match_version(self):
        for tag in ['v0.3.1', 'main', 'v0.3.2-beta', 'v0.3.2\n']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                version_info('version: 0.3.2+5\n', tag)

    def test_build_number_required(self):
        for version in ['0.3.2', '0.3.2+0', '0.3.2-beta+5']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                version_info('version: ' + version, 'v0.3.2')

    def test_production_apk_allows_other_plugin_abis(self):
        self.validate()

    def test_reject_wrong_package_or_version(self):
        for original, replacement in [('space.su7.xiabanwang', 'com.example.debug'),
                                      ("versionCode='5'", "versionCode='4'"),
                                      ("versionName='0.3.2'", "versionName='0.3.1'")]:
            with self.subTest(replacement=replacement), self.assertRaises(ValueError):
                self.validate(badging=self.badging.replace(original, replacement))

    def test_reject_wrong_missing_or_multiple_signers(self):
        for certificates in ['', self.certificates.replace('a' * 64, 'b' * 64),
                             self.certificates + self.certificates.replace('#1', '#2')]:
            with self.subTest(certificates=certificates), self.assertRaises(ValueError):
                self.validate(certificates=certificates)

    def test_reject_wrong_flutter_architecture(self):
        for members in [[], ['lib/x86_64/libflutter.so'], self.members + ['lib/x86_64/libflutter.so']]:
            with self.subTest(members=members), self.assertRaises(ValueError):
                self.validate(members=members)

    def test_both_version_and_build_must_increase(self):
        check_upgrade({'version': '0.3.3', 'versionCode': 6}, self.info)
        for current in [self.info, {'version': '0.3.1', 'versionCode': 6},
                        {'version': '0.3.3', 'versionCode': 5}]:
            with self.subTest(current=current), self.assertRaises(ValueError):
                check_upgrade(current, self.info)


if __name__ == '__main__':
    unittest.main()
