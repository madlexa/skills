#!/usr/bin/env bash
# smoke_test.sh — end-to-end test of niblet hooks against a temp project.
#
# Verifies:
#   1. observe.sh auto-creates .niblet/ and adds it to .gitignore
#   2. observe.sh writes JSONL events to raw/<session>.jsonl
#   3. on_subagent_stop.sh creates PENDING_FAST and increments task_counter
#   4. on_prompt_submit.sh emits FAST reminder when PENDING_FAST is set
#   5. on_stop.sh creates PENDING_DEEP
#   6. on_prompt_submit.sh emits DEEP reminder when PENDING_DEEP is set
#   7. Counter ≥ 5 triggers PENDING_DEEP via on_subagent_stop.sh
#   8. Idempotency: re-running on a project with existing .gitignore entry adds no dup
#
# Exits non-zero on any failure.

set -e

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$PLUGIN_DIR/hooks"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAIL=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
title() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# Build a fake hook event JSON
event() {
  local session="$1" tool="$2" cwd="$3"
  printf '{"session_id":"%s","tool_name":"%s","cwd":"%s","tool_input":{"x":1},"tool_response":"ok"}' \
    "$session" "$tool" "$cwd"
}

# --- Setup: fresh git project ---
PROJECT="$TMP/project"
mkdir -p "$PROJECT"
( cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t \
   && echo "# test" > README.md && git add . && git commit -qm "init" )

SESSION="test-$(date +%s)"
STORE="$PROJECT/.niblet"

title "1. observe.sh auto-init"
event "$SESSION" "Read" "$PROJECT" | "$HOOKS/observe.sh" post >/dev/null
[ -d "$STORE/raw" ] && pass ".niblet/raw exists" || fail "raw dir missing"
[ -d "$STORE/log" ] && pass ".niblet/log exists" || fail "log dir missing"
grep -qxF ".niblet/" "$PROJECT/.gitignore" && pass ".gitignore contains .niblet/" \
  || fail ".gitignore missing entry"

title "2. JSONL event written"
RAW="$STORE/raw/${SESSION}.jsonl"
[ -s "$RAW" ] && pass "raw log non-empty" || fail "raw log empty"
grep -q '"tool":"Read"' "$RAW" && pass "event recorded" || fail "event missing"

title "3. on_subagent_stop creates PENDING_FAST + counter"
event "$SESSION" "" "$PROJECT" | "$HOOKS/on_subagent_stop.sh" >/dev/null
[ -f "$STORE/PENDING_FAST" ] && pass "PENDING_FAST exists" || fail "no PENDING_FAST"
[ "$(cat "$STORE/task_counter" 2>/dev/null)" = "1" ] && pass "counter=1" \
  || fail "counter wrong: $(cat "$STORE/task_counter" 2>/dev/null)"

title "4. on_prompt_submit emits FAST reminder"
OUT="$(event "$SESSION" "" "$PROJECT" | "$HOOKS/on_prompt_submit.sh")"
echo "$OUT" | grep -q "NIBLET CHECKPOINT (fast)" \
  && pass "FAST reminder emitted" || fail "no FAST reminder"
echo "$OUT" | grep -q "\.claude/kb" && pass "reminder mentions kb path" || fail "no kb path"

title "5. on_stop creates PENDING_DEEP"
rm -f "$STORE/PENDING_DEEP"
event "$SESSION" "" "$PROJECT" | "$HOOKS/on_stop.sh" >/dev/null
[ -f "$STORE/PENDING_DEEP" ] && pass "PENDING_DEEP exists" || fail "no PENDING_DEEP"

title "6. on_prompt_submit emits DEEP reminder when both pending"
OUT="$(event "$SESSION" "" "$PROJECT" | "$HOOKS/on_prompt_submit.sh")"
echo "$OUT" | grep -q "NIBLET CHECKPOINT (deep)" \
  && pass "DEEP reminder emitted" || fail "no DEEP reminder"
echo "$OUT" | grep -q "Task / Agent tool" && pass "reminder mentions Task tool" \
  || fail "no Task tool mention"

title "7. counter ≥ threshold triggers PENDING_DEEP"
# Reset state
rm -f "$STORE/PENDING_FAST" "$STORE/PENDING_DEEP" "$STORE/task_counter"
for i in 1 2 3 4 5; do
  event "$SESSION" "" "$PROJECT" | "$HOOKS/on_subagent_stop.sh" >/dev/null
done
COUNT="$(cat "$STORE/task_counter")"
[ "$COUNT" = "5" ] && pass "counter=5 after 5 calls" || fail "counter=$COUNT"
[ -f "$STORE/PENDING_DEEP" ] && pass "PENDING_DEEP triggered at threshold" \
  || fail "PENDING_DEEP not triggered"

title "8. .gitignore add is idempotent"
LINES_BEFORE="$(grep -cxF ".niblet/" "$PROJECT/.gitignore")"
event "$SESSION" "Read" "$PROJECT" | "$HOOKS/observe.sh" post >/dev/null
LINES_AFTER="$(grep -cxF ".niblet/" "$PROJECT/.gitignore")"
[ "$LINES_BEFORE" = "$LINES_AFTER" ] && pass "no duplicate entries (lines=$LINES_AFTER)" \
  || fail "duplicate added: $LINES_BEFORE → $LINES_AFTER"

printf '\n'
if [ "$FAIL" = "0" ]; then
  printf '\033[32mAll checks passed.\033[0m\n'
  exit 0
else
  printf '\033[31m%d check(s) failed.\033[0m\n' "$FAIL"
  exit 1
fi
