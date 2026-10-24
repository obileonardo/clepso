#!/usr/bin/env python3
"""Deploy only the reviewed static website to Clepso's existing Vercel project."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
PROJECT = "prj_ZTZiAhmv5oejW0DcgdzavbllW2qT"
SCOPE = "obileonardos-projects"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prod", action="store_true", help="publish after the fixed-directory preflight; otherwise inspect only")
    args = parser.parse_args()
    for required in ["index.html", "vercel.json", "assets/public.css", "app/index.html", "updates/appcast.xml"]:
        if not (SITE / required).is_file():
            raise SystemExit("Missing website input: " + required)
    for path in SITE.rglob("*"):
        if path.is_symlink() or path.suffix in {".xcconfig", ".p12", ".pem", ".key", ".sqlite", ".mobileprovision"} or path.name.startswith(".env"):
            raise SystemExit("Unexpected private or linked website input; review the site directory")
    base = ["vercel", "deploy", "--project", PROJECT, "--scope", SCOPE, "--yes", "--json"]
    result = subprocess.run(base + ["--dry"], cwd=SITE, capture_output=True, text=True, check=True)
    inventory = json.loads(result.stdout)
    if Path(inventory["basePath"]).resolve() != SITE.resolve() or not 20 <= inventory["fileCount"] <= 2000:
        raise SystemExit("Unexpected deployment root or file inventory; nothing published")
    if not args.prod:
        print(json.dumps({key: inventory[key] for key in ["basePath", "fileCount", "totalSize"]}, indent=2))
        return
    print("Website preflight passed: " + str(inventory["fileCount"]) + " files from site/", file=sys.stderr)
    subprocess.run(base + ["--prod"], cwd=SITE, check=True)


if __name__ == "__main__":
    main()
