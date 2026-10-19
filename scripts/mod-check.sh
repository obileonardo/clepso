#!/bin/bash
# Checks Clepso's Claude Code mod (docs/specs/mod-bridge.md §2.3, §11): the marketplace and the plugin pass
# `claude plugin validate --strict`, the mod's hooks and calls are exactly the reviewed ones, and its tests pass under
# `claude plugin test`. Every `claude` command runs with HOME and CLAUDE_CONFIG_DIR in a throwaway folder, so the real
# ~/.claude is never read or written. Prints the validate output (it is the published audit of what the mod calls).
#
#   scripts/mod-check.sh            needs the `claude` CLI (2.1.287 or later)
#   scripts/mod-check.sh --optional passes with a note when `claude` is not installed (contributor CI)
set -uo pipefail
cd "$(dirname "$0")/.."

MOD=mod/claude-code
PLUGIN=$MOD/plugins/clepso-limits
EXPECTED_HOOKS='hooks: session.measure'
EXPECTED_CALLS='calls: $.process.run, $.session.id, $.session.surfaces, $.session.version'

if ! command -v claude >/dev/null 2>&1; then
    [ "${1:-}" = "--optional" ] && { echo "claude CLI not installed: mod checks skipped (contributor mode)"; exit 0; }
    echo "the claude CLI is needed to validate and test the mod"; exit 1
fi

sandbox=$(mktemp -d /tmp/clepso-modcheck.XXXXXX) || exit 1
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/.claude"
isolated() {
    env HOME="$sandbox" CLAUDE_CONFIG_DIR="$sandbox/.claude" DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 "$@"
}

echo "claude $(isolated claude --version)"
files_before=$(find "$MOD" -type f | sort)
status=0
out=$(isolated claude plugin validate --strict "$MOD" 2>&1) || status=1
printf '%s\n' "$out"
out=$(isolated claude plugin validate --strict "$PLUGIN" 2>&1) || status=1
printf '%s\n' "$out"
grep -qF "$EXPECTED_HOOKS" <<<"$out" || { echo "hooks changed: expected '$EXPECTED_HOOKS'"; status=1; }
grep -qF "$EXPECTED_CALLS" <<<"$out" || { echo "calls changed: expected '$EXPECTED_CALLS' (update the spec, the consent copy and PRIVACY §4.4 first)"; status=1; }
[ "$(grep -cE '❯ .* hooks: ' <<<"$out")" -eq 1 ] && [ "$(grep -cE '❯ .* calls: ' <<<"$out")" -eq 1 ] || { echo "more than one hooks module"; status=1; }
grep -q 'env reads:\|env writes:\|state reads:\|state writes:' <<<"$out" && { echo "the mod must not read or write environment variables or state"; status=1; }

out=$(cd "$PLUGIN" && isolated claude plugin test . 2>&1) || status=1
printf '%s\n' "$out"
grep -qE '^ *[1-9][0-9]* pass' <<<"$out" && grep -qE '^ *0 fail' <<<"$out" || { echo "mod tests did not all pass"; status=1; }

# Nothing the checks ran may leave files in the mod (types, caches): the bundle must stay the reviewed source.
extra=$(comm -13 <(printf '%s\n' "$files_before") <(find "$MOD" -type f | sort))
[ -z "$extra" ] || { echo "the checks left files in the mod: $extra"; status=1; }
[ $status -eq 0 ] && echo "mod validated (strict), calls pinned, tests passed; real ~/.claude untouched (isolated HOME)"
exit $status
