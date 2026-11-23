"""Exercise deploy orchestration with local stubs; never contacts GitHub."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DeployTests(unittest.TestCase):
    def run_deploy(self, *, prepare_fails=False, confirm='1', app_version='1.2.6', publish='1', missing_asset=False):
        with tempfile.TemporaryDirectory(prefix='xxmac-deploy-test-') as folder:
            root = Path(folder)
            shutil.copy(ROOT / 'publish_dmg.sh', root)
            (root / 'Sources/xxMac').mkdir(parents=True)
            (root / 'xxMac.app/Contents').mkdir(parents=True)
            for path, version in [('Sources/xxMac/Info.plist', '1.2.6'),
                                  ('xxMac.app/Contents/Info.plist', app_version)]:
                with (root / path).open('wb') as file:
                    plistlib.dump({'CFBundleShortVersionString': version,
                                   'CFBundleVersion': version}, file)
            (root / 'scripts').mkdir()
            (root / 'scripts/prepare_update.sh').write_text('''#!/bin/bash
set -eu
printf '%s' "$RELEASE_TAG" > prepared-tag
if [ "${PREPARE_FAIL:-0}" = 1 ]; then exit 7; fi
mkdir -p "$UPDATE_OUTPUT_DIR"
if [ "${MISSING_ASSET:-0}" = 1 ]; then exit 0; fi
touch "$UPDATE_OUTPUT_DIR/xxMac-1.2.6.zip" "$UPDATE_OUTPUT_DIR/appcast.xml"
''')
            bindir = root / 'bin'
            bindir.mkdir()
            stubs = {
                'codesign': '#!/bin/sh\necho "Authority=test certificate leaf"\n',
                'ditto': '#!/bin/sh\nmkdir -p "$2"\n',
                'hdiutil': '#!/bin/sh\nexit 0\n',
                'gh': '''#!/usr/bin/env python3
import json, sys
from pathlib import Path
with Path('gh-calls.jsonl').open('a') as f:
    f.write(json.dumps(sys.argv[1:]) + '\\n')
''',
            }
            for name, contents in stubs.items():
                path = bindir / name
                path.write_text(contents)
                path.chmod(0o755)
            env = dict(os.environ, PATH=f'{bindir}:/usr/bin:/bin:/usr/sbin:/sbin',
                       VERSION='1.2.6', SKIP_BUILD='1', PUBLISH_GITHUB_RELEASE=publish,
                       GH_BIN=str(bindir / 'gh'), GITHUB_RELEASE_TITLE='Test release',
                       GITHUB_RELEASE_NOTES='Test notes', GITHUB_RELEASE_CONFIRM=confirm,
                       RELEASE_TAG='v1.2.6', MISSING_ASSET='1' if missing_asset else '0', PREPARE_FAIL='1' if prepare_fails else '0')
            env.pop('UPDATE_OUTPUT_DIR', None)
            result = subprocess.run(['bash', 'publish_dmg.sh'], cwd=root, env=env,
                                    stdin=subprocess.DEVNULL, capture_output=True, text=True)
            calls_file = root / 'gh-calls.jsonl'
            calls = [json.loads(line) for line in calls_file.read_text().splitlines()] if calls_file.exists() else []
            tag = (root / 'prepared-tag').read_text() if (root / 'prepared-tag').exists() else None
            return result, calls, tag

    def test_publish_includes_dmg_zip_and_appcast_with_custom_tag(self):
        result, calls, tag = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(tag, 'v1.2.6')
        release = next(call for call in calls if call[:2] == ['release', 'create'])
        self.assertEqual(release[2], 'v1.2.6')
        self.assertEqual([Path(value).name for value in release[3:6]],
                         ['xxMac-1.2.6.dmg', 'xxMac-1.2.6.zip', 'appcast.xml'])

    def test_failed_update_generation_never_publishes(self):
        result, calls, _ = self.run_deploy(prepare_fails=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[:2] == ['release', 'create'] for call in calls))

    def test_declining_confirmation_keeps_release_local(self):
        result, calls, tag = self.run_deploy(confirm='0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(tag, 'v1.2.6')
        self.assertFalse(any(call[:2] == ['release', 'create'] for call in calls))

    def test_local_only_deploy_still_generates_updates(self):
        result, calls, tag = self.run_deploy(publish='0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(tag, 'v1.2.6')
        self.assertEqual(calls, [])

    def test_missing_update_assets_never_publish(self):
        result, calls, _ = self.run_deploy(missing_asset=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[:2] == ['release', 'create'] for call in calls))

    def test_stale_skip_build_app_never_publishes(self):
        result, calls, tag = self.run_deploy(app_version='1.2.5')
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(tag)
        self.assertFalse(any(call[:2] == ['release', 'create'] for call in calls))


if __name__ == '__main__':
    unittest.main()
