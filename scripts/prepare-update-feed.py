#!/usr/bin/env python3
"""Generate a signed Sparkle feed from an already notarized release. Never publishes or generates private keys."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

VERSION = "2.10.0"
SHA256 = "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
ACCOUNT = "com.elvisobi.clepso.updates"
PUBLIC_KEY = "WeaRornZqBUmFaOutT62FtvopukvrlEZPCEiapwbCpk="
ROOT = Path(__file__).resolve().parent.parent


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    args = parser.parse_args()
    if not re.fullmatch(r"v\d+\.\d+\.\d+-alpha\.\d+", args.tag):
        raise SystemExit("This feed accepts reviewed alpha tags only")
    release = ROOT / "build/release" / args.tag
    app = release / "export/Clepso.app"
    dmg = release / ("Clepso-" + args.tag[1:] + ".dmg")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("SUPublicEDKey") != PUBLIC_KEY or not info.get("SURequireSignedFeed") or not info.get("SUVerifyUpdateBeforeExtraction"):
        raise SystemExit("Release must pin the update key and require feed/archive signatures")
    expected = (release / "SHA256SUMS").read_text().split()[0]
    if digest(dmg) != expected:
        raise SystemExit("DMG checksum mismatch")
    subprocess.run(["xcrun", "stapler", "validate", str(dmg)], check=True)
    cache = ROOT / ".tools" / ("Sparkle-" + VERSION + ".tar.xz")
    cache.parent.mkdir(exist_ok=True)
    if not cache.exists():
        with urllib.request.urlopen("https://github.com/sparkle-project/Sparkle/releases/download/" + VERSION + "/Sparkle-" + VERSION + ".tar.xz", timeout=120) as response:
            data = response.read(32 * 1024 * 1024 + 1)
        if len(data) > 32 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != SHA256:
            raise SystemExit("Official Sparkle tool archive checksum mismatch")
        cache.write_bytes(data)
    if digest(cache) != SHA256:
        raise SystemExit("Cached Sparkle tool archive checksum mismatch")
    with tempfile.TemporaryDirectory(prefix="clepso-update-tools-") as temporary:
        work = Path(temporary)
        with tarfile.open(cache) as archive:
            for name in ("generate_keys", "generate_appcast", "sign_update", "BinaryDelta"):
                member = archive.getmember("./bin/" + name)
                if not member.isfile() or member.size > 32 * 1024 * 1024:
                    raise SystemExit("Unexpected tool archive entry")
                target = work / "bin" / name
                target.parent.mkdir(exist_ok=True)
                with archive.extractfile(member) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
                os.chmod(target, 0o700)
        tools = work / "bin"
        public = subprocess.check_output([str(tools / "generate_keys"), "--account", ACCOUNT, "-p"], text=True).strip()
        if public != PUBLIC_KEY:
            raise SystemExit("The Keychain update-signing key does not match the released public key")
        feed_dir = release / "update-feed"
        feed_dir.mkdir(exist_ok=True)
        # Stage only the validated DMG. No credentials or app configuration enter the feed directory.
        staged = work / "archives"
        staged.mkdir()
        shutil.copy2(dmg, staged / dmg.name)
        notes = ROOT / "docs/release-notes" / (args.tag + ".md")
        if notes.exists():
            shutil.copy2(notes, staged / (dmg.stem + ".md"))
        subprocess.run([str(tools / "generate_appcast"), "--account", ACCOUNT, "--maximum-deltas", "0", "--channel", "alpha",
                        "--download-url-prefix", "https://github.com/obileonardo/clepso/releases/download/" + args.tag + "/",
                        "--link", "https://clepso-app.vercel.app/", "--embed-release-notes", str(staged)], check=True)
        feed = staged / "appcast.xml"
        tree = ET.parse(feed)
        namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
        item = tree.find("./channel/item")
        if item is None or item.findtext("sparkle:version", namespaces=namespace) != str(info["CFBundleVersion"]):
            raise SystemExit("Generated feed version does not match the signed app")
        enclosure = item.find("enclosure")
        if enclosure is None or not enclosure.get("{" + namespace["sparkle"] + "}edSignature"):
            raise SystemExit("Generated feed has no archive signature")
        for name in ("appcast.xml", "appcast.xml.sig"):
            candidate = staged / name
            if candidate.exists():
                shutil.copy2(candidate, feed_dir / name)
        # Preserve the signed bytes exactly. The deployment must not transform XML or embedded notes.
        print("Signed feed prepared:", feed_dir / "appcast.xml")
        print("Publish only after its GitHub DMG URL is live; deploy these exact signed bytes to /updates/.")


if __name__ == "__main__":
    main()
