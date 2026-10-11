"""Run with python3 -m unittest discover -s awakeTests -p 'ReleaseScriptsTests.py'."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ReleaseScriptsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / "scripts", self.root / "scripts")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands.jsonl"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        COMMAND_LOG=str(self.log), TEST_VERSION="0.6.0-beta.1",
                        TEST_RELEASE_EXISTS="1", DEVELOPER_DIR="/test/Xcode")
        self.stub("gh", '''#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
with open(os.environ['COMMAND_LOG'], 'a') as f: f.write(json.dumps(a) + '\\n')
if a[:2] == ['repo', 'view']: print('PMGWork/awake')
elif a[0] == 'api':
    query = a[-1]
    if 'select(' in query:
        if os.environ['TEST_RELEASE_EXISTS'] == '1': print('123')
    elif query == '.draft': print('true')
    elif query == '.assets[].name':
        print('Awake-' + os.environ['TEST_VERSION'] + '.zip')
        print('appcast.xml')
''')
        self.stub("git", '''#!/bin/sh
case "$1" in
  remote) echo https://github.com/PMGWork/awake.git ;;
  rev-parse)
    case "$*" in *refs/tags*) exit 1 ;; *) echo abc123 ;; esac ;;
esac
''')

    def stub(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def run_script(self, name, *args):
        return subprocess.run(["sh", str(self.root / "scripts" / name), *args],
                              env=self.env, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_version_mapping(self):
        for version, expected in [
            ("0.6.0", "0.6.0|0.6.0|false"),
            ("0.6.0-beta.1", "0.6.0|0.6.0b1|true"),
            ("0.6.0-beta.255", "0.6.0|0.6.0b255|true"),
        ]:
            with self.subTest(version=version):
                result = subprocess.run(
                    ["sh", "-c", 'VERSION="$1"; . "$2"; printf "%s|%s|%s" '
                     '"$MARKETING_VERSION" "$BUILD_VERSION" "$IS_PRERELEASE"',
                     "sh", version, str(self.root / "scripts/release-version.sh")],
                    capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)

    def test_invalid_versions_fail_before_external_commands(self):
        for version in ["0.6", "0.6.0-beta.0", "0.6.0-beta.01", "0.6.0-beta.256",
                        "0.6.0-beta.1000", "0.6.0-rc.1", "0.6.0-beta.1;id"]:
            for script in ["release.sh", "package.sh"]:
                with self.subTest(version=version, script=script):
                    self.assertNotEqual(self.run_script(script, version).returncode, 0)
        self.assertFalse(self.log.exists())

    def test_publish_beta_does_not_replace_latest(self):
        result = self.run_script("release.sh", "--publish", "0.6.0-beta.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["release", "edit", "v0.6.0-beta.1", "--draft=false",
                       "--prerelease=true", "--latest=false"], self.calls())
        self.assertIn(["workflow", "run", "update-feeds.yml", "--ref", "main",
                       "--repo", "PMGWork/awake"], self.calls())

    def test_publish_stable_marks_latest(self):
        self.env["TEST_VERSION"] = "0.6.0"
        result = self.run_script("release.sh", "--publish", "0.6.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["release", "edit", "v0.6.0", "--draft=false",
                       "--prerelease=false", "--latest"], self.calls())

    def prepare_artifacts(self):
        dist = self.root / "dist"
        dist.mkdir()
        (dist / "Awake-0.6.0-beta.1.zip").touch()
        (dist / "appcast.xml").write_text('<sparkle:version>0.6.0b1</sparkle:version>')

    def test_new_beta_draft_is_prerelease(self):
        self.prepare_artifacts()
        self.env["TEST_RELEASE_EXISTS"] = "0"
        result = self.run_script("release.sh", "--skip-build", "0.6.0-beta.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        creation = next(c for c in self.calls() if c[:2] == ["release", "create"])
        for flag in ["--prerelease", "--latest=false", "--draft", "--verify-tag"]:
            self.assertIn(flag, creation)

    def test_reusing_beta_draft_uploads_without_creation_flags(self):
        self.prepare_artifacts()
        result = self.run_script("release.sh", "--skip-build", "0.6.0-beta.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        upload = next(c for c in self.calls() if c[:2] == ["release", "upload"])
        self.assertIn("--clobber", upload)
        self.assertNotIn("--prerelease", upload)
        self.assertNotIn("--latest=false", upload)

    def test_package_passes_apple_beta_version_to_xcode(self):
        self.stub("xcodebuild", '''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['COMMAND_LOG'], 'a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')
if '-version' in sys.argv: print('Xcode test')
else: sys.exit(42)
''')
        result = self.run_script("package.sh", "0.6.0-beta.1")
        self.assertEqual(result.returncode, 42)
        build = next(c for c in self.calls() if "build" in c)
        self.assertIn("MARKETING_VERSION=0.6.0", build)
        self.assertIn("CURRENT_PROJECT_VERSION=0.6.0b1", build)

    def test_dry_run_does_not_publish(self):
        result = self.run_script("release.sh", "--publish", "--dry-run", "0.6.0-beta.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--prerelease=true --latest=false", result.stdout)
        self.assertFalse(any(c[:2] == ["release", "edit"] for c in self.calls()))


if __name__ == "__main__":
    unittest.main()
