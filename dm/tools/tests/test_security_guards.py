"""Security regressions: changed tools cannot execute; private Git data is refused."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]


def module(name):
    spec = importlib.util.spec_from_file_location(name, REPO / 'scripts' / (name + '.py'))
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result


build = module('build_dotnet_tools')
guard = module('repository_guard')


class ToolIntegrity(unittest.TestCase):
    def test_changed_missing_extra_and_outside_artifacts_are_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            output = Path(d); folder = output / 'dmsh_xlate'; folder.mkdir()
            exe = folder / 'dmsh_xlate'; exe.write_bytes(b'not executable')
            manifest = {'source_sha256': 'verified-source', 'files': build.artifact_hashes(folder)}
            (folder / 'build-manifest.json').write_text(json.dumps(manifest))
            with mock.patch.object(build, 'OUTPUT', output), mock.patch.object(build, 'source_digest', return_value='verified-source'):
                self.assertEqual(build.verify_tool('dmsh_xlate'), exe)
                exe.write_bytes(b'tampered')
                with self.assertRaises(RuntimeError): build.verify_tool('dmsh_xlate')
                exe.write_bytes(b'not executable')
                extra = folder / 'extra.dll'; extra.write_bytes(b'new DLL')
                with self.assertRaises(RuntimeError): build.verify_tool('dmsh_xlate')
                extra.unlink()
                with self.assertRaises(RuntimeError): build.verify_tool('dmsh_xlate', output / 'historical/dmsh_xlate')
                with mock.patch.object(build, 'source_digest', return_value='changed-source'):
                    with self.assertRaises(RuntimeError): build.verify_tool('dmsh_xlate')
                exe.unlink()
                with self.assertRaises(RuntimeError): build.verify_tool('dmsh_xlate')

    def test_dependency_source_change_changes_digest(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); source = root / 'helper.cs'; source.write_bytes(b'one')
            with mock.patch.object(build, 'REPO', root), mock.patch.object(build, 'source_files', return_value=[source]):
                old = build.source_digest(); source.write_bytes(b'two')
                self.assertNotEqual(old, build.source_digest())


class GitPrivacy(unittest.TestCase):
    def test_private_paths_and_content_are_blocked_without_values(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(guard, 'REPO', Path(d)):
            root = Path(d)
            def git(*args):
                return subprocess.run(['git', *args], cwd=root, check=True, capture_output=True)
            git('init', '-q')
            (root / 'safe.txt').write_text('ordinary source\n'); git('add', 'safe.txt')
            self.assertEqual(guard.scan()[0], [])
            (root / 'PROD.KEYS').write_text('private test fixture, no actual keys'); git('add', 'PROD.KEYS')
            self.assertTrue(any('Forbidden' in b for b in guard.scan()[0]))
            git('rm', '--cached', '-q', 'PROD.KEYS')
            # Construct a synthetic matching value without embedding a secret-like literal in Git.
            value = 'ab' * 32
            (root / 'safe.txt').write_text('master_key_00 = ' + value + '\n'); git('add', 'safe.txt')
            bad, _ = guard.scan()
            self.assertTrue(any('Potential secret' in b for b in bad))
            self.assertFalse(any(value in b for b in bad))


class ApprovedDestination(unittest.TestCase):
    def check(self, visibility='public', private=False, fork=True, actual_url=None, configured_url=None):
        expected = 'Shipsen7/nxnative'
        url = 'https://github.com/' + expected + '.git'
        values = {
            ('config', '--get', 'nxnative.approvedRepository'): expected.encode(),
            ('config', '--get', 'nxnative.approvedVisibility'): visibility.encode(),
            ('remote', 'get-url', '--push', 'origin'): (configured_url or url).encode(),
        }
        info = dict(nameWithOwner=expected, isPrivate=private, isFork=fork)
        with mock.patch.object(guard, 'git', side_effect=lambda *args: values[args]), \
             mock.patch.object(guard.subprocess, 'check_output', return_value=json.dumps(info).encode()):
            guard.approved_remote(actual_url)

    def test_explicitly_approved_public_fork_is_accepted(self):
        self.check(actual_url='https://github.com/Shipsen7/nxnative.git')

    def test_changed_visibility_or_actual_push_url_is_rejected(self):
        with self.assertRaises(RuntimeError): self.check(private=True)
        with self.assertRaises(RuntimeError): self.check(actual_url='https://github.com/another/repository.git')
        with self.assertRaises(RuntimeError): self.check(configured_url='https://github.com/seedds/nxnative.git')

    def test_private_mode_requires_independent_repository(self):
        with self.assertRaises(RuntimeError): self.check(visibility='private', private=True, fork=True)
        self.check(visibility='private', private=True, fork=False)

    def test_absent_visibility_approval_is_rejected(self):
        with self.assertRaises(RuntimeError): self.check(visibility='')


if __name__ == '__main__': unittest.main()
