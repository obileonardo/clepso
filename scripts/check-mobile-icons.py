#!/usr/bin/env python3
"""Reject alpha/transparency in the mobile App Store icons before building or uploading."""
from pathlib import Path
import struct


def opaque_icon(data):
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return False
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    if (width, height, depth, color) != (1024, 1024, 8, 2):
        return False
    offset = 8
    while offset + 12 <= len(data):
        size = struct.unpack(">I", data[offset:offset + 4])[0]
        chunk = data[offset + 4:offset + 8]
        if chunk == b"tRNS" or offset + size + 12 > len(data):
            return False
        if chunk == b"IEND":
            return True
        offset += size + 12
    return False


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    for target in ["ClepsoPhone", "ClepsoWatch"]:
        path = root / "App" / target / "Assets.xcassets/AppIcon.appiconset/AppIcon.png"
        if not opaque_icon(path.read_bytes()):
            raise SystemExit(target + ": expected a 1024px opaque RGB PNG without an alpha channel")
    print("Phone and Watch App Store icons are opaque 1024px RGB PNGs.")
