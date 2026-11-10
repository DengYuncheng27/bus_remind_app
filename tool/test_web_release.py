import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import ci_plan
import web_release


class PlanTests(unittest.TestCase):
    def test_docs_do_not_build_or_deploy(self):
        self.assertFalse(any(ci_plan.changed_checks(['AGENTS.md', 'docs/workflow.md']).values()))

    def test_native_and_test_changes_do_not_deploy_web(self):
        for path in ['android/app/build.gradle.kts', 'ios/Runner/AppDelegate.swift', 'test/home_test.dart']:
            checks = ci_plan.changed_checks([path])
            self.assertTrue(checks['flutter'])
            self.assertFalse(checks['web'])

    def test_web_shared_and_pipeline_changes_run_full_checks(self):
        for path in ['lib/main.dart', 'assets/icon.png', 'pubspec.lock', 'web/sw.js',
                     '.github/workflows/ci.yml', 'tool/web_release.py']:
            self.assertTrue(all(ci_plan.changed_checks([path]).values()))

    def test_deploy_requires_exact_merged_pr_to_this_main(self):
        sha = 'a' * 40
        pull = {'merged_at': '2026-11-10', 'merge_commit_sha': sha,
                'base': {'ref': 'main', 'repo': {'full_name': 'owner/repo'}}}
        self.assertTrue(ci_plan.merged_pr([pull], 'owner/repo', sha))
        for pulls in [[], [{**pull, 'merged_at': None}], [{**pull, 'merge_commit_sha': 'b' * 40}]]:
            self.assertFalse(ci_plan.merged_pr(pulls, 'owner/repo', sha))
        self.assertFalse(ci_plan.merged_pr([pull], 'other/repo', sha))


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        previous = Path.cwd()
        self.root = Path(temporary.name)
        os.chdir(self.root)
        self.addCleanup(os.chdir, previous)
        def git(*args):
            return subprocess.check_output(['git', *args], stderr=subprocess.PIPE, text=True).strip()
        git('init', '-b', 'main')
        git('config', 'user.email', 'test@example.invalid')
        git('config', 'user.name', 'Artifact test')
        git('config', 'core.hooksPath', '/dev/null')
        Path('source').write_text('tracked')
        git('add', 'source')
        git('commit', '-m', 'test')
        self.sha = git('rev-parse', 'HEAD')
        self.web = Path('build/web')
        self.web.mkdir(parents=True)
        for name in ['index.html', 'flutter_bootstrap.js', 'sw.js', 'web-push.js', 'download.html']:
            (self.web / name).write_text(name)
        self.directory = Path('build/release')

    def test_package_contains_only_web_with_verifiable_provenance(self):
        web_release.package(self.directory, self.sha)
        manifest = web_release.verify_artifacts(self.directory, self.sha)
        self.assertEqual(set(manifest['parts']), {'client.tar.gz'})
        with tarfile.open(self.directory / 'client.tar.gz') as archive:
            self.assertEqual(len(archive.getmembers()), 5)
            self.assertTrue(all(m.name.startswith('client/') and m.isfile() for m in archive))
        with (self.directory / 'client.tar.gz').open('ab') as stream:
            stream.write(b'tampered')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            web_release.verify_artifacts(self.directory, self.sha)

    def test_dirty_source_or_wrong_commit_cannot_be_released(self):
        with self.assertRaisesRegex(ValueError, 'checked-out'):
            web_release.package(self.directory, 'b' * 40)
        Path('source').write_text('changed during build')
        with self.assertRaisesRegex(RuntimeError, 'Tracked source'):
            web_release.package(self.directory, self.sha)

    def test_missing_required_entry_is_rejected(self):
        (self.web / 'sw.js').unlink()
        with self.assertRaisesRegex(RuntimeError, 'sw.js'):
            web_release.package(self.directory, self.sha)

    def test_pr_cannot_deploy_and_superseded_main_never_connects(self):
        with patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'pull_request'}):
            with self.assertRaisesRegex(RuntimeError, 'main push'):
                web_release.deploy(self.directory, self.sha)
        web_release.package(self.directory, self.sha)
        with patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF': 'refs/heads/main',
                                     'GITHUB_REPOSITORY': 'owner/repo'}), \
                patch.object(web_release, 'latest_main', return_value='b' * 40), \
                patch.object(web_release, 'run') as run, contextlib.redirect_stdout(io.StringIO()):
            web_release.deploy(self.directory, self.sha)
            run.assert_not_called()

    def test_deploy_checks_client_ancestry_and_preserves_backend_snapshot(self):
        web_release.package(self.directory, self.sha)
        state = {'clientRevision': 'c' * 40, 'backendRevision': 'b' * 40, 'backendPath': '/live/backend'}
        environment = {'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF': 'refs/heads/main',
                       'GITHUB_REPOSITORY': 'owner/repo', 'GITHUB_STEP_SUMMARY': str(self.root / 'summary'),
                       'CD_SSH_HOST': 'example.invalid', 'CD_SSH_USER': 'root', 'CD_SSH_PORT': '22',
                       'CD_SSH_PRIVATE_KEY': 'test key', 'CD_SSH_KNOWN_HOSTS': 'test host'}
        def execute(command, **kwargs):
            if command[0] == 'git':
                self.assertEqual(command, ['git', 'merge-base', '--is-ancestor', state['clientRevision'], self.sha])
            else:
                header = json.loads(kwargs['stdin'].readline())
                self.assertEqual(header['expectedRevision'], state['backendRevision'])
                self.assertEqual(header['expectedRelease'], state['backendPath'])
                self.assertEqual(set(header['parts']), {'client.tar.gz'})
                kwargs['stdout'].write(json.dumps({'clientRevision': self.sha}).encode() + b'\n')
            return subprocess.CompletedProcess(command, 0)
        with patch.dict(os.environ, environment), patch.object(web_release, 'latest_main', return_value=self.sha), \
                patch.object(web_release, 'run', return_value=json.dumps(state)), \
                patch.object(web_release.subprocess, 'run', side_effect=execute), \
                patch.object(web_release, 'check_public_health') as health, contextlib.redirect_stdout(io.StringIO()):
            web_release.deploy(self.directory, self.sha)
            health.assert_called_once()


if __name__ == '__main__':
    unittest.main()
