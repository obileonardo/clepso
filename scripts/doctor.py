#!/usr/bin/env python3
"""Check host release access without changing credentials, permissions or Git state."""
import argparse
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile


def run(command, timeout=20):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout, result.stderr
    except (OSError, subprocess.TimeoutExpired) as error:
        return 1, "", str(error)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disk-image-probe", action="store_true",
                        help="create and remove a small temporary DMG; never mounts it")
    parser.add_argument("--notary-profile", default="clepso-notary")
    args = parser.parse_args()
    os.chdir(Path(__file__).resolve().parent.parent)
    failures = []

    def report(name, okay, detail):
        print("{:<5} {:<25} {}".format("PASS" if okay else "FAIL", name, detail), flush=True)
        if not okay:
            failures.append(name)

    print("Clepso host access checks (not a build, signing or release gate)", flush=True)
    code, output, error = run(["xcode-select", "-p"])
    report("Xcode selection", code == 0, output.strip() if code == 0 else error.strip())
    free_gb = shutil.disk_usage("/").free / (1024 ** 3)
    report("Internal free space", free_gb >= 8, "{:.1f} GiB available; release requires 8 GiB".format(free_gb))

    for host in ("github.com", "api.github.com", "apple.com"):
        # Run DNS in a child so an unresponsive resolver has a bounded timeout.
        code, _, error = run([sys.executable, "-c",
                              "import socket,sys; socket.getaddrinfo(sys.argv[1],443)", host], timeout=10)
        report("DNS: " + host, code == 0, "resolved" if code == 0 else "resolver unavailable or denied")

    code, _, error = run(["git", "ls-remote", "origin", "HEAD"])
    report("Git remote read", code == 0, "origin reachable" if code == 0 else error.strip().splitlines()[-1] if error.strip() else "failed")
    code, _, _ = run(["gh", "api", "user", "--jq", ".login"])
    report("GitHub authentication", code == 0, "API authenticated" if code == 0 else "API unavailable or authentication failed; no token printed")

    with tempfile.TemporaryDirectory(prefix="clepso-doctor-") as temporary:
        scratch = Path(temporary)
        connection = socket.socket(socket.AF_UNIX)
        try:
            connection.bind(str(scratch / "probe.sock"))
            report("Local socket binding", True, "permitted")
        except OSError as error:
            report("Local socket binding", False, str(error))
        finally:
            connection.close()

        log = scratch / "logging.log"
        code, _, error = run(["/bin/bash", "-c",
                              'set -e; exec > >(tee "$1"); printf "diagnostic\\n"', "doctor", str(log)])
        report("Release logging", code == 0 and log.exists() and log.read_text() == "diagnostic\n",
               "process substitution available" if code == 0 else error.strip())

        code, _, error = run(["/usr/sbin/diskutil", "info", "-plist", "/"])
        report("DiskManagement access", code == 0,
               "available" if code == 0 else "DiskManagement/DiskArbitration unavailable; retry after permission change")

        code, output, _ = run(["security", "find-identity", "-v", "-p", "codesigning"])
        visible = code == 0 and '"Developer ID Application:' in output
        report("Developer ID identity", visible,
               "visible" if visible else "none visible; may be sandbox access, locked Keychain or missing certificate/private key")

        code, _, error = run(["xcrun", "notarytool", "history", "--keychain-profile", args.notary_profile,
                              "--output-format", "json"], timeout=30)
        report("Notary profile access", code == 0,
               "Keychain profile and Apple service available" if code == 0 else error.strip()[-240:] or "unavailable")

        if args.disk_image_probe:
            contents = scratch / "contents"
            contents.mkdir()
            (contents / "probe.txt").write_text("Clepso temporary host diagnostic.\n")
            destination = scratch / "probe.dmg"
            code, output, error = run(["hdiutil", "create", "-srcfolder", str(contents),
                                  "-format", "UDZO", "-volname", "ClepsoDiagnostic", str(destination)], timeout=30)
            report("Disk image creation", code == 0 and destination.is_file(),
                   "temporary DMG created; removed on exit" if code == 0 else
                   (error.strip() or output.strip())[-240:] or "failed (exit {})".format(code))

    print("\n{} failed check(s).".format(len(failures)))
    if failures:
        print("A failed check inside a sandbox does not establish that the Mac is misconfigured.")
        print("Compare this command after changing the CLI/IDE permission profile; do not export secrets to work around it.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
