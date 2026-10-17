#!/usr/bin/env python3 -I
"""Independent oracle for the fixture corpus, increment 1.7 rows (DATA_MODEL §5.1, statusline-shim §6).

Reads only each fixture's raw stdin and meta.json and applies the spec's rules, so the expectations it writes never
come from the Swift code they check. Re-running is safe: the 1.7 rows are replaced, and the allowlist move from
"dropped" to "forwarded" happens once.

    python3 -I scripts/fixture-oracle.py [--check]

--check exits non-zero if any expected.json would change (for CI-style use).
"""
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "Sources/TestFixtures/Resources/claude-code"
MAX_INT = 2 ** 53

# §6 (founder decision 17 Oct 2026, A4 amended): newly forwarded raw fields.
NEW_FORWARDED = ["cost.total_duration_ms", "cost.total_api_duration_ms", "cost.total_lines_added", "cost.total_lines_removed"]

# DATA_MODEL §5.1, 1.7 rows: raw path, metric kind, value rule.
ROWS = [
    (["context_window", "total_output_tokens"], "sessionOutputTokens", "tokens"),
    (["cost", "total_duration_ms"], "wallDuration", "duration"),
    (["cost", "total_api_duration_ms"], "apiDuration", "duration"),
    (["cost", "total_lines_added"], "linesAdded", "count"),
    (["cost", "total_lines_removed"], "linesRemoved", "count"),
    (["prompt_cache", "hit_ratio"], "cacheHitPct", "ratio"),
    (["prompt_cache", "requests"], "cacheRequests", "count"),
    (["prompt_cache", "misses"], "cacheMisses", "count"),
    (["prompt_cache", "warm"], "cacheWarm", "flag"),
]
NEW_KINDS = {kind for _, kind, _ in ROWS}

MISSING = object()


def lookup(obj, path):
    for key in path:
        if not isinstance(obj, dict) or key not in obj:
            return MISSING
        obj = obj[key]
    return obj


def is_int(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and float(v).is_integer() and 0 <= v <= MAX_INT


def helper_value(raw, rule):
    """What the helper forwards: the value if it passes §6, else None (null, counted as a scrub)."""
    if rule in ("tokens", "duration", "count"):
        return raw if is_int(raw) else None
    if rule == "ratio":
        return raw if isinstance(raw, (int, float)) and not isinstance(raw, bool) and 0 <= raw <= 1 else None
    if rule == "flag":
        return raw if isinstance(raw, bool) else None
    raise ValueError(rule)


def measurement(value, rule):
    if value is None:
        return {"kind": "absent", "reason": "providerNull"}
    if rule == "tokens":
        return {"kind": "tokens", "value": int(value)}
    if rule == "duration":
        return {"kind": "duration", "milliseconds": int(value)}
    if rule == "count":
        return {"kind": "count", "value": int(value)}
    if rule == "flag":
        return {"kind": "flag", "value": value}
    # ratio → percent, multiplied in decimal from the shortest text of the number.
    pct = Decimal(repr(float(value))) * 100
    return {"kind": "percent", "value": format(pct.normalize(), "f")}


def acceptable_string(s, max_len):
    """The helper's string scrub (PRIVACY_AND_SECURITY §4), for `version` → sourceVersion."""
    if not isinstance(s, str) or len(s.encode()) > max_len or any(not 0x20 <= ord(c) <= 0x7E for c in s):
        return False
    if any(t in s for t in ("/", "\\", "@", "$HOME", "sk-ant-", "AKIA", "ghp_", "Bearer ")):
        return False
    if re.search(r"(^|[^A-Za-z0-9])sk-", s) or re.search(r"[A-Za-z0-9+/=]{32,}", s):
        return False
    return True


def process(fixture: Path, check: bool) -> bool:
    expected_path, meta_path = fixture / "expected.json", fixture / "meta.json"
    if not expected_path.exists() or not meta_path.exists():
        return False
    expected = json.loads(expected_path.read_text())
    meta = json.loads(meta_path.read_text())
    before = json.dumps(expected, sort_keys=True)
    start = datetime.strptime(meta["clock"]["start"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    accepted = [e.get("accepted", False) for e in expected.get("parser", {}).get("events", [])]

    labels, new_obs, forwarded_now, scrubbed_now, extra_scrubs = {}, [], set(), set(), 0
    for i, event in enumerate(meta.get("events", [])):
        if "file" not in event or i >= len(accepted) or not accepted[i]:
            continue
        stdin = json.loads((fixture / event["file"]).read_text())
        if not isinstance(stdin, dict):
            continue
        for key in NEW_FORWARDED:
            raw = lookup(stdin, key.split("."))
            if raw is MISSING:
                continue
            if raw is None or helper_value(raw, "count") is not None:
                forwarded_now.add(key)
            else:
                scrubbed_now.add(key)
                extra_scrubs += 1
        session_id = stdin.get("session_id")
        if not isinstance(session_id, str):
            continue                                   # no session_ref: the mapper drops session rows
        label = labels.setdefault(session_id, "ABCD"[len(labels)])
        version = stdin.get("version")
        observed = (start + timedelta(seconds=event.get("atOffsetSeconds", 0))).strftime("%Y-%m-%dT%H:%M:%SZ")
        for path, kind, rule in ROWS:
            raw = lookup(stdin, path)
            if raw is MISSING:
                continue
            m = measurement(None if raw is None else helper_value(raw, rule), rule)
            new_obs.append({"subject": "session", "metricKind": kind, "measurement": m, "observedAt": observed,
                            "source": "officialLocalTelemetry",
                            "sourceVersion": version if acceptable_string(version, 32) else None,
                            "quality": "unknown" if m["kind"] == "absent" else "reported", "sessionRef": label})

    if "observations" in expected:
        expected["observations"] = [o for o in expected["observations"] if o.get("metricKind") not in NEW_KINDS] + new_obs
    forwarded = expected.get("forwarded")
    if forwarded and any(k in forwarded.get("droppedByConstruction", []) for k in NEW_FORWARDED):
        forwarded["droppedByConstruction"] = [k for k in forwarded["droppedByConstruction"] if k not in NEW_FORWARDED]
        forwarded["fields"] = forwarded.get("fields", []) + sorted(forwarded_now - set(forwarded.get("fields", [])))
        forwarded["scrubbed"] = forwarded.get("scrubbed", []) + sorted(scrubbed_now - set(forwarded.get("scrubbed", [])))
        expected["parser"]["health"]["scrubbed"] = expected["parser"]["health"].get("scrubbed", 0) + extra_scrubs

    changed = json.dumps(expected, sort_keys=True) != before
    if changed and not check:
        expected_path.write_text(json.dumps(expected, indent=2, ensure_ascii=False) + "\n")
    return changed


def main():
    check = "--check" in sys.argv
    changed = [f.name for f in sorted(ROOT.glob("*/**/")) if (f / "expected.json").exists() and process(f, check)]
    print(("would change: " if check else "updated: ") + (", ".join(changed) or "none"))
    sys.exit(1 if check and changed else 0)


if __name__ == "__main__":
    main()
