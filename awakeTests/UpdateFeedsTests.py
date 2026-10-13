"""Run with python3 -m unittest discover -s awakeTests -p '*Tests.py'."""

import importlib.util
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location(
    "update_feeds", Path(__file__).resolve().parents[1] / "scripts/generate-update-feeds.py")
feeds = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feeds)
REPO = "PMGWork/awake"


def release(tag, prerelease=False, draft=False):
    return dict(tag_name=tag, prerelease=prerelease, draft=draft,
                published_at="2026-10-12T00:00:00Z", assets=[dict(name="appcast.xml")])


def appcast(tag):
    version = feeds.release_version(release(tag, "-beta." in tag))
    return f'''<rss xmlns:sparkle="{feeds.SPARKLE}"><channel><item>
    <title>Awake</title><sparkle:version>{version}</sparkle:version>
    <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
    <description><![CDATA[<h2>What's Changed</h2><p>Release notes</p>]]></description>
    <enclosure url="https://github.com/{REPO}/releases/download/{tag}/Awake-{tag[1:]}.zip"
    length="12345" type="application/octet-stream" sparkle:edSignature="original-signature"/>
    </item></channel></rss>'''.encode()


def versions(data):
    return [item.findtext(feeds.sparkle("version"))
            for item in ET.fromstring(data).findall("./channel/item")]


class UpdateFeedsTests(unittest.TestCase):
    def build(self, releases, loader=None):
        return feeds.build_feeds(releases, loader or (lambda r: appcast(r["tag_name"])), REPO)

    def test_beta_feed_includes_stable_and_excludes_drafts(self):
        data = self.build([release("v0.6.0-beta.1", True), release("v0.5.0"),
                           release("v0.6.0-beta.2", True, draft=True)])
        self.assertEqual(versions(data["stable"]), ["0.5.0"])
        self.assertCountEqual(versions(data["beta"]), ["0.5.0", "0.6.0b1"])

    def test_migration_release_keeps_060_beta_opt_in(self):
        data = self.build([release("v0.5.1"), release("v0.6.0-beta.1", True),
                           release("v0.5.0"), release("v0.6.0", draft=True)])
        self.assertCountEqual(versions(data["stable"]), ["0.5.1", "0.5.0"])
        self.assertCountEqual(versions(data["beta"]), ["0.5.1", "0.5.0", "0.6.0b1"])

    def test_formal_release_is_available_to_beta_users(self):
        data = self.build([release("v0.6.0-beta.1", True), release("v0.6.0")])
        self.assertEqual(versions(data["stable"]), ["0.6.0"])
        self.assertIn("0.6.0", versions(data["beta"]))

    def test_signed_enclosure_requirements_and_notes_are_preserved(self):
        data = self.build([release("v0.5.0"), release("v0.6.0-beta.1", True)])
        original = ET.fromstring(appcast("v0.6.0-beta.1")).find("./channel/item")
        copied = next(i for i in ET.fromstring(data["beta"]).findall("./channel/item")
                      if i.findtext(feeds.sparkle("version")) == "0.6.0b1")
        self.assertEqual(copied.find("enclosure").attrib, original.find("enclosure").attrib)
        self.assertEqual(copied.findtext(feeds.sparkle("minimumSystemVersion")), "26.0")
        self.assertEqual(copied.findtext("description"), original.findtext("description"))
        self.assertEqual(copied.findtext(feeds.sparkle("shortVersionString")), "0.6.0-beta.1")

    def test_beta_feed_falls_back_to_stable_when_no_beta_exists(self):
        data = self.build([release("v0.5.0")])
        self.assertEqual(versions(data["beta"]), versions(data["stable"]))

    def test_invalid_published_appcasts_fail_instead_of_publishing_partial_feeds(self):
        for source in [appcast("v0.5.0").replace(b'original-signature', b''),
                       appcast("v0.5.0").replace(b'0.5.0', b'0.4.0'),
                       appcast("v0.5.0").replace(b'https://github.com/', b'https://other.example/'),
                       appcast("v0.5.0").replace(b'length="12345"', b'length="0"'),
                       b"invalid XML"]:
            with self.subTest(source=source):
                with self.assertRaises((ValueError, ET.ParseError)):
                    self.build([release("v0.5.0")], lambda r: source)

    def test_enclosure_version_attribute_from_older_feeds_is_supported(self):
        root = ET.fromstring(appcast("v0.5.0"))
        item = root.find("./channel/item")
        item.remove(item.find(feeds.sparkle("version")))
        item.find("enclosure").set(feeds.sparkle("version"), "0.5.0")
        data = self.build([release("v0.5.0")], lambda r: ET.tostring(root))
        self.assertEqual(ET.fromstring(data["stable"]).find("./channel/item/enclosure")
                         .get(feeds.sparkle("version")), "0.5.0")

    def test_release_flags_must_match_tag(self):
        for r in [release("v0.6.0-beta.1"), release("v0.6.0", True),
                  release("v0.6.0-beta.256", True)]:
            with self.subTest(release=r):
                with self.assertRaises(ValueError):
                    self.build([release("v0.5.0"), r])

    def test_missing_current_appcast_fails_but_pre_sparkle_release_is_ignored(self):
        historical = release("v0.1.0")
        historical["assets"] = []
        self.assertEqual(versions(self.build([historical, release("v0.5.0")])["stable"]), ["0.5.0"])
        for r in [release("v0.6.0-beta.1", True), release("v0.6.0")]:
            r["assets"] = []
            with self.assertRaises(ValueError):
                self.build([release("v0.5.0"), r])

    def test_empty_feed_is_rejected(self):
        with self.assertRaises(ValueError):
            self.build([])


if __name__ == "__main__":
    unittest.main()
