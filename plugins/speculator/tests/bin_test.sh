#!/usr/bin/env bash
# bin_test.sh — verify the bin/speculator CLI wrapper.
#
# Checks:
#   1. bin/speculator exists and is executable
#   2. `bin/speculator --help` exits 0 and prints usage
#
# Exit 0 = all checks pass; non-zero = a check failed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
BIN="$PLUGIN_ROOT/bin/speculator"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[ -f "$BIN" ] || fail "bin/speculator not found"
[ -x "$BIN" ] || fail "bin/speculator is not executable"

out="$("$BIN" --help 2>&1)"
rc=$?
[ "$rc" -eq 0 ] || fail "bin/speculator --help exited $rc"
printf '%s\n' "$out" | grep -q "Usage: speculator" || fail "bin/speculator --help did not print usage"

echo "OK: bin/speculator wrapper"
