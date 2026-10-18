#!/usr/bin/env python3 -I
"""Builds a synthetic home folder for the screenshot probe: no real usage data, same result on every run.

Writes <home>/.claude/stats-cache.json shaped like the file Claude Code keeps for /stats (only the fields Clepso's
StatsReader reads, plus a fake longest-session id it must ignore), covering about 14 months up to yesterday.
Every number comes from a fixed random seed.

Usage: python3 -I scripts/probe-home.py <home dir> [YYYY-MM-DD]   (the date defaults to today)

Then launch a debug build with -ClepsoHome <home dir> -ClepsoDataDirectory <data dir> -ClepsoProbeOutput <dir>
-ClepsoProbeDemo YES (see README, "Run it safely").
"""
import json
import random
import sys
from datetime import date, timedelta
from pathlib import Path

MODELS = {                       # model id → share of a day's tokens, output fraction of its total
    "claude-opus-5-5": (0.62, 0.012),
    "claude-sonnet-5-5": (0.30, 0.015),
    "claude-haiku-4-5-20251001": (0.08, 0.02),
}


def build(today: date) -> dict:
    rng = random.Random(20261017)
    end = today - timedelta(days=1)                       # the file runs through yesterday
    start = end - timedelta(days=420)
    days, daily_tokens = [], []
    totals = {m: {"inputTokens": 0, "outputTokens": 0, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0} for m in MODELS}
    hour_counts = {h: 0 for h in range(24)}
    sessions_total = messages_total = 0
    day = start
    while day <= end:
        weekend = day.weekday() >= 5
        active = rng.random() < (0.35 if weekend else 0.8)
        if active:
            sessions = rng.randint(1, 3 if weekend else 6)
            messages = sessions * rng.randint(15, 70)
            tokens = int(messages * rng.uniform(1_500, 6_000))
            days.append({"date": day.isoformat(), "messageCount": messages, "sessionCount": sessions,
                         "toolCallCount": int(messages * rng.uniform(1.2, 2.4))})
            by_model = {}
            for model, (share, output_fraction) in MODELS.items():
                t = int(tokens * share * rng.uniform(0.7, 1.3))
                if t == 0:
                    continue
                by_model[model] = t
                out = int(t * output_fraction)
                cache_write = int(t * 0.04)
                inp = int(t * 0.001)
                totals[model]["outputTokens"] += out
                totals[model]["cacheCreationInputTokens"] += cache_write
                totals[model]["inputTokens"] += inp
                totals[model]["cacheReadInputTokens"] += t - out - cache_write - inp
            daily_tokens.append({"date": day.isoformat(), "tokensByModel": by_model})
            for _ in range(sessions):
                hour_counts[min(23, max(0, int(rng.gauss(14, 3.5))))] += 1
            sessions_total += sessions
            messages_total += messages
        day += timedelta(days=1)
    return {
        "version": 5,
        "lastComputedDate": end.isoformat(),
        "dailyActivity": days,
        "dailyModelTokens": daily_tokens,
        "modelUsage": totals,
        "totalSessions": sessions_total,
        "totalMessages": messages_total,
        "longestSession": {"sessionId": "synthetic-session-id", "timestamp": f"{end.isoformat()}T10:00:00.000Z",
                           "duration": 4 * 3600_000 + 12 * 60_000, "messageCount": 212},
        "firstSessionDate": f"{days[0]['date']}T09:00:00.000Z" if days else None,
        "hourCounts": {str(h): n for h, n in hour_counts.items() if n},
    }


def main() -> None:
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    home = Path(sys.argv[1])
    today = date.fromisoformat(sys.argv[2]) if len(sys.argv) == 3 else date.today()
    claude = home / ".claude"
    claude.mkdir(parents=True, exist_ok=True)
    (claude / "stats-cache.json").write_text(json.dumps(build(today), indent=1) + "\n")
    print(f"synthetic home ready: {home}")


if __name__ == "__main__":
    main()
