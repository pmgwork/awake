#!/usr/bin/env python3
"""Combine signed release appcasts into stable and beta feeds; no signing keys needed."""

import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET


SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")


def sparkle(name):
    return f"{{{SPARKLE}}}{name}"


def release_version(release):
    match = re.fullmatch(r"v(\d+\.\d+\.\d+)(?:-beta\.([1-9]\d{0,2}))?",
                         release["tag_name"])
    if not match:
        return None
    base, beta = match.groups()
    if beta and int(beta) > 255:
        raise ValueError(f"Invalid beta number: {release['tag_name']}")
    if bool(beta) != bool(release["prerelease"]):
        raise ValueError(f"Release type does not match tag: {release['tag_name']}")
    return f"{base}b{beta}" if beta else base


def release_items(release, appcast, repository):
    version = release_version(release)
    root = ET.fromstring(appcast)
    items = []
    expected_url = (f"https://github.com/{repository}/releases/download/"
                    f"{release['tag_name']}/Awake-{release['tag_name'][1:]}.zip")
    for item in root.findall("./channel/item"):
        enclosure = item.find("enclosure")
        if enclosure is None:
            continue
        item_version = item.findtext(sparkle("version")) or enclosure.get(sparkle("version"))
        if item_version != version:
            continue
        if not enclosure.get(sparkle("edSignature")):
            raise ValueError(f"Unsigned enclosure: {release['tag_name']}")
        if enclosure.get("url", "").lower() != expected_url.lower():
            raise ValueError(f"Unexpected archive URL: {release['tag_name']}")
        if int(enclosure.get("length", "0")) <= 0:
            raise ValueError(f"Invalid archive length: {release['tag_name']}")
        if item.find(sparkle("channel")) is not None:
            raise ValueError(f"Unexpected Sparkle channel: {release['tag_name']}")
        # Preserve the signed enclosure and all OS requirements / release notes.
        copied = deepcopy(item)
        if release["prerelease"]:
            short_version = copied.find(sparkle("shortVersionString"))
            if short_version is None:
                short_version = ET.SubElement(copied, sparkle("shortVersionString"))
            short_version.text = release["tag_name"][1:]
        items.append(copied)
    if not items:
        raise ValueError(f"No matching signed update: {release['tag_name']}")
    return items


def build_feeds(releases, load_appcast, repository):
    stable, beta = [], []
    for release in sorted(releases, key=lambda r: r.get("published_at") or "", reverse=True):
        if release["draft"] or not release.get("published_at"):
            continue
        if release_version(release) is None:
            continue
        if not any(asset["name"] == "appcast.xml" for asset in release["assets"]):
            # Historical releases before Sparkle have no appcast.
            if release["prerelease"] or tuple(map(int, release["tag_name"][1:].split("."))) >= (0, 2, 0):
                raise ValueError(f"Release has no appcast: {release['tag_name']}")
            continue
        items = release_items(release, load_appcast(release), repository)
        beta.extend(items)
        if not release["prerelease"]:
            stable.extend(items)
    if not stable:
        raise ValueError("No signed stable release available; refusing to publish empty feeds.")
    feeds = {}
    for name, items in [("stable", stable), ("beta", beta)]:
        root = ET.Element("rss", version="2.0")
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = f"Awake {name.title()} Updates"
        ET.SubElement(channel, "link").text = f"https://github.com/{repository}"
        ET.SubElement(channel, "description").text = f"Awake {name} update feed"
        for item in items:
            channel.append(deepcopy(item))
        feeds[name] = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    return feeds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--output", type=Path, default=Path("dist/update-feeds"))
    args = parser.parse_args()
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repository):
        parser.error("repository must be owner/name")
    pages = json.loads(subprocess.check_output([
        "gh", "api", f"repos/{args.repository}/releases?per_page=100", "--paginate", "--slurp"
    ], text=True))
    releases = [release for page in pages for release in page]
    with tempfile.TemporaryDirectory() as temp:
        def load_appcast(release):
            folder = Path(temp) / release["tag_name"]
            subprocess.run(["gh", "release", "download", release["tag_name"],
                            "--repo", args.repository, "--pattern", "appcast.xml",
                            "--dir", str(folder)], check=True)
            return (folder / "appcast.xml").read_bytes()

        feeds = build_feeds(releases, load_appcast, args.repository)
    args.output.mkdir(parents=True, exist_ok=True)
    for name, data in feeds.items():
        (args.output / f"{name}.xml").write_bytes(data)
        print(f"Generated {args.output / (name + '.xml')}")


if __name__ == "__main__":
    main()
