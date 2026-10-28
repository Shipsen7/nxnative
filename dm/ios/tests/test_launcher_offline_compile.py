"""Compile the real iOS launcher under the GUI's outbound-IP restriction."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
POLICY = '(version 1) (allow default) (deny network-outbound (remote ip "*:*"))'


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun')
                     and Path('/usr/bin/sandbox-exec').is_file(), 'requires Xcode on macOS')
class OfflineLauncherCompile(unittest.TestCase):
    def test_production_launcher_typechecks_without_relaxing_sandboxing(self):
        sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
        with tempfile.TemporaryDirectory(prefix='launcher-offline-') as directory:
            result = subprocess.run([
                '/usr/bin/sandbox-exec', '-p', POLICY, 'xcrun', '--sdk', 'iphoneos', 'swiftc',
                '-typecheck', '-swift-version', '5', '-target', 'arm64-apple-ios26.0', '-sdk', sdk,
                '-module-cache-path', directory,
                str(ROOT / 'dm/ios/Sources/Launcher.swift'),
                str(ROOT / 'dm/ios/Sources/LauncherSettings.swift'),
            ], text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
