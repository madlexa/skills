#!/usr/bin/env bash
# alias_normalize_test.sh — regression test for alias slug normalization.
#
# `add entity` slugifies the entity name ([^a-z0-9]+ -> "-"), but `add alias`
# used to store the alias verbatim. Aliases live in the comma-delimited aliases
# column of the pipe-delimited INDEX.entities.md table, which is read back by
# splitting on `|` then `,` (src/lib/index-reader.ts). An alias containing `|`
# or `,` therefore corrupted the row: it mis-columned on read and the alias
# became unrecoverable (could neither be looked up nor removed by name).
#
# The fix normalizes the alias with the same slugify() add_entity uses, so a
# pipe/comma collapses to "-" and the index stays well-formed.
#
# Exit 0 = alias is normalized and the index round-trips; non-zero = regression.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
BIN="$PLUGIN_ROOT/bin/speculator"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
skip() { printf 'SKIP: %s\n' "$1"; exit 0; }

command -v node >/dev/null 2>&1 || skip "node not found on PATH"
[ -x "$BIN" ] || fail "bin/speculator not found or not executable"
[ -f "$PLUGIN_ROOT/dist/cli.js" ] || fail "dist/cli.js missing — run 'npm run build'"

KB="$(mktemp -d)"
trap 'rm -rf "$KB"' EXIT

spec() { "$BIN" --dir "$KB" "$@"; }

spec init "$KB" --no-example >/dev/null 2>&1 || "$BIN" init "$KB" --no-example >/dev/null 2>&1 || fail "init failed"
spec add entity payment "the payment gateway" >/dev/null 2>&1 || fail "add entity failed"

# A pipe in the alias is the corruption trigger. It must be normalized to "pay-x"
# (slugify collapses "|" runs to a single "-"), not stored verbatim.
spec add alias payment 'pay|x' >/dev/null 2>&1 || fail "add alias 'pay|x' failed"

INDEX="$KB/INDEX.entities.md"
[ -f "$INDEX" ] || fail "INDEX.entities.md missing"

# The raw pipe must never reach the aliases column — that would break the table.
if grep -q 'pay|x' "$INDEX"; then
  fail "raw 'pay|x' (unnormalized pipe) leaked into the index — table is corrupt"
fi
grep -q 'pay-x' "$INDEX" || fail "normalized alias 'pay-x' not found in index"

# The normalized alias must round-trip: lookup by it resolves the entity.
out="$(spec get pay-x 2>&1)" || fail "get by normalized alias failed: $out"
printf '%s' "$out" | grep -qi 'payment' || fail "get pay-x did not resolve the payment entity: $out"

# Comma is the other table delimiter; it must also be normalized, not split into
# a phantom alias.
spec add alias payment 'a,b' >/dev/null 2>&1 || fail "add alias 'a,b' failed"
spec get a-b >/dev/null 2>&1 || fail "comma alias not normalized to 'a-b'"

echo "OK: add_alias normalizes pipe/comma to a safe slug; index round-trips"
