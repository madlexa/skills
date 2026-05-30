#!/usr/bin/env bash
# index_order_test.sh — regression test for index sort/search comparator parity.
#
# `index rebuild` (src/commands/index.ts) writes INDEX rows in sorted order, and
# the incremental upsert/remove paths (src/lib/document.ts bsearch*) read those
# rows back with binary search. Both MUST use the same ordering.
#
# The rebuild used `String.localeCompare` (no locale arg), which picks up the
# host's LC_COLLATE. For non-English collations (Danish, Norwegian, Czech,
# Estonian, Lithuanian, …) localeCompare orders the plain slug charset
# [a-z0-9-] differently from raw codepoint — e.g. Danish sorts "aa" AFTER "ab".
# The binary search assumes codepoint order, so after a rebuild on such a host a
# `remove` searches the wrong slot, fails to find the row, and leaves an orphan
# index entry pointing at a now-deleted file. The fix makes the rebuild sort by
# codepoint too, so the invariant holds regardless of host locale.
#
# This test reproduces that on a host where a divergent locale is installed; if
# none is available it SKIPS (exit 0) rather than giving a false pass/fail.
#
# Exit 0 = parity holds (or no divergent locale to test); non-zero = regression.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
BIN="$PLUGIN_ROOT/bin/speculator"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
skip() { printf 'SKIP: %s\n' "$1"; exit 0; }

command -v node >/dev/null 2>&1 || skip "node not found on PATH"
[ -x "$BIN" ] || fail "bin/speculator not found or not executable"
[ -f "$PLUGIN_ROOT/dist/cli.js" ] || fail "dist/cli.js missing — run 'npm run build'"

# Two slugs where codepoint order is X < Y. We need a locale that reverses them
# (localeCompare(X,Y) > 0), so the rebuild writes [Y, X] but binary search still
# expects [X, Y]. Danish/Norwegian collate "aa" as "å" → after "ab".
X="aa"; Y="ab"
LOC=""
for cand in da_DK.UTF-8 nb_NO.UTF-8 nn_NO.UTF-8 fo_FO.UTF-8 da_DK nb_NO; do
  # Ask node, under this locale, whether localeCompare reverses the codepoint order.
  res="$(LC_ALL="$cand" LANG="$cand" node -e '
    const x=process.argv[1], y=process.argv[2];
    const lc=Math.sign(x.localeCompare(y));
    const cp=x<y?-1:(x>y?1:0);
    process.stdout.write(lc+" "+cp);
  ' "$X" "$Y" 2>/dev/null)" || continue
  lc="${res% *}"; cp="${res#* }"
  if [ -n "$lc" ] && [ "$lc" != "$cp" ] && [ "$lc" != "0" ]; then
    LOC="$cand"; break
  fi
done
[ -n "$LOC" ] || skip "no installed locale reverses '$X'/'$Y' order; cannot exercise comparator parity on this host"

KB="$(mktemp -d)"
trap 'rm -rf "$KB"' EXIT
spec() { LC_ALL="$LOC" LANG="$LOC" "$BIN" "$@"; }

spec init "$KB" --no-example >/dev/null 2>&1 || fail "init failed"
spec --dir "$KB" add entity "$X" "x" >/dev/null 2>&1 || fail "add entity $X failed"
spec --dir "$KB" add entity "$Y" "y" >/dev/null 2>&1 || fail "add entity $Y failed"

# Force a full rebuild — written in the host locale's collation order.
spec --dir "$KB" index rebuild >/dev/null 2>&1 || fail "index rebuild failed"

INDEX="$KB/INDEX.entities.md"
[ -f "$INDEX" ] || fail "INDEX.entities.md missing after rebuild"
grep -q "entities/$X.md" "$INDEX" || fail "$X row missing after rebuild"
grep -q "entities/$Y.md" "$INDEX" || fail "$Y row missing after rebuild"

# Remove the codepoint-smaller entity — binary-searches the rebuilt index.
spec --dir "$KB" remove "$X" >/dev/null 2>&1 || fail "remove $X failed"

# With the comparator bug, binary search misses the row under locale $LOC and
# the orphan survives even though the file was unlinked.
if grep -q "entities/$X.md" "$INDEX"; then
  fail "orphan: $X row left in index after remove under locale $LOC (rebuild/search comparator mismatch)"
fi
grep -q "entities/$Y.md" "$INDEX" || fail "$Y row wrongly removed"
[ ! -f "$KB/entities/$X.md" ] || fail "$X.md not unlinked"

echo "OK: index rebuild/binary-search comparator parity (locale $LOC)"
