#!/usr/bin/env python3
"""Validate explicit APNs key files privately; apply only to an explicitly selected Supabase project."""
import argparse
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile


def key(path):
    resolved = path.expanduser().resolve(strict=True)
    info = resolved.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or not 100 <= info.st_size <= 8192:
        raise ValueError("Key must be a bounded regular file owned by this user")
    match = re.fullmatch(r"(?:AuthKey_|Apple Auth Key |Auth Key )([A-Z0-9]{10})\.p8", resolved.name)
    if not match:
        raise ValueError("Keep the downloaded key filename with its 10-character Apple key ID")
    pem = resolved.read_text()
    # The key travels to Node on stdin, never in process arguments or log output.
    validator = """const crypto=require('node:crypto');let s='';process.stdin.setEncoding('utf8');process.stdin.on('data',v=>s+=v);process.stdin.on('end',()=>{try{const k=crypto.createPrivateKey(s);process.exit(k.asymmetricKeyType==='ec'&&k.asymmetricKeyDetails.namedCurve==='prime256v1'?0:1)}catch{process.exit(1)}});"""
    result = subprocess.run(["node", "-e", validator], input=pem, text=True, capture_output=True)
    if result.returncode:
        raise ValueError("Expected an Apple P-256 private key")
    return match[1], pem


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-ref", required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--sandbox-key", type=Path)
    parser.add_argument("--production-key", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9]{20}", args.project_ref) or not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
        parser.error("Use an explicit project reference and 10-character Apple Team ID")
    if not args.sandbox_key and not args.production_key:
        parser.error("Provide at least one environment's key file")
    secrets = {"APNS_TEAM_ID": args.team_id}
    for environment, path in [("SANDBOX", args.sandbox_key), ("PRODUCTION", args.production_key)]:
        if path:
            identifier, pem = key(path)
            secrets["APNS_" + environment + "_KEY_ID"] = identifier
            secrets["APNS_" + environment + "_KEY_P8"] = pem
    if args.sandbox_key and args.production_key and secrets["APNS_SANDBOX_KEY_ID"] == secrets["APNS_PRODUCTION_KEY_ID"]:
        parser.error("Use separate environment-specific keys")
    print("Validated keys for " + ", ".join(name for name, path in [("Sandbox", args.sandbox_key), ("Production", args.production_key)] if path))
    if not args.apply:
        print("Dry run only; no secrets uploaded. Review the target before adding --apply.")
        return
    path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", prefix="clepso-apns-", suffix=".env", delete=False) as stream:
            path = Path(stream.name)
            os.chmod(path, 0o600)
            for name, value in secrets.items():
                stream.write(name + "=" + json.dumps(value) + "\n")
        result = subprocess.run(["supabase", "secrets", "set", "--project-ref", args.project_ref, "--env-file", str(path)],
                                capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError("Supabase did not accept the update; secret output was withheld")
        print("APNs server secrets updated. Redeploy the function and verify Apple acceptance; no push was sent by this helper.")
    finally:
        if path is not None:
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, RuntimeError):
        raise SystemExit("APNs setup did not complete. Check the selected files, project, and CLI authentication; no secret output was printed.")
