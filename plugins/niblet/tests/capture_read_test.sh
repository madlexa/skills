#!/usr/bin/env bash
# capture_read_test.sh — code-walker auto-trigger on repeated reads.
set -e

PROJECT_ROOT="/Users/Aleksey.Dobrynin/projects/madlexa/skills"
SCRIPT="$PROJECT_ROOT/plugins/niblet/bin/niblet-capture-read"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

# Lower threshold so we don't need 5 reads.
export NIBLET_CODE_WALKER_THRESHOLD=2
export NIBLET_CODE_WALKER_COOLDOWN_HOURS=0

mkdir -p "$TMP/plugins/niblet/src"
echo "x" > "$TMP/plugins/niblet/src/x.py"

# First read: no queue.
"$SCRIPT" --project-root "$TMP" --session s1 --path plugins/niblet/src/x.py --tool Read >/dev/null || fail "first capture failed"
[ ! -d "$TMP/.niblet/code_walker_queue" ] || fail "queue should not exist after first read"

# Second read: queue created for component plugins/niblet.
out=$("$SCRIPT" --project-root "$TMP" --session s1 --path plugins/niblet/src/y.py --tool Read)
printf '%s' "$out" | grep -q "code-walker queued" || fail "second read should queue code-walker"
[ -f "$TMP/.niblet/code_walker_queue/"*.queue ] || fail "queue file missing"
[ -f "$TMP/.niblet/.code-walker-last-run" ] || fail "last-run marker missing"

# Duplicate queue for the same component should be suppressed.
out2=$("$SCRIPT" --project-root "$TMP" --session s1 --path plugins/niblet/src/z.py --tool Read)
printf '%s' "$out2" | grep -q "code-walker queued" && fail "duplicate queue should be suppressed"
count=$(find "$TMP/.niblet/code_walker_queue" -maxdepth 1 -name '*.queue' -type f | wc -l | tr -d ' ')
[ "$count" = "1" ] || fail "expected exactly one queue file, got $count"

echo "capture-read tests passed"
