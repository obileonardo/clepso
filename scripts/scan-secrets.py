#!/usr/bin/env python3
"""Scan tracked and publishable untracked source; report locations, never matching values."""
from pathlib import Path
import re
import subprocess

PATTERN = re.compile(rb"sk-ant-[A-Za-z0-9_-]{3,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|xox[abp]-[A-Za-z0-9-]{10,}|sb_secret_[A-Za-z0-9_-]{8,}")


def locations(data):
    return [number for number, line in enumerate(data.splitlines(), 1)
            if b"secret-scan: allow" not in line and PATTERN.search(line)]


def main():
    root = Path(__file__).resolve().parents[1]
    # --cached includes tracked files even if a later ignore rule matches them.
    files = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root)
    found = False
    for name in sorted(set(files.split(b"\0")) - {b""}):
        path = root / name.decode()
        if path.is_symlink() or not path.is_file():
            continue
        data = path.read_bytes()
        if b"\0" in data[:8192]:
            continue  # Same text-only scope as the original grep -I scanner.
        for line in locations(data):
            print(f"{name.decode()}:{line}: secret-shaped string (value withheld)")
            found = True
    if found:
        return 1
    print("No secret-shaped strings in tracked or publishable untracked source; ignored local runtime files excluded.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
