#!/usr/bin/env bash
# smoke_test.sh — end-to-end test of niblet v0.2 contract.
#
# Tests the security and lifecycle contract, not just plumbing:
#
#   1. observe.sh auto-initializes .niblet/ + .gitignore on first tool call
#   2. observe.sh writes SANITIZED JSONL (no tool_response/tool_input content,
#      only tool name + safe path + exit code)
#   3. on_stop.sh works on text-only session — store + gitignore appear even
#      with no prior tool calls
#   4. on_stop.sh creates PENDING_FAST per-session and increments counter
#   5. on_prompt_submit.sh emits FAST reminder for THIS session
#   6. Stop × DEFAULT_THRESHOLD does NOT create PENDING_DEEP (safety net
#      is 20 by default; mid-session work is uninterrupted)
#   7. on_session_end.sh unconditionally creates PENDING_DEEP
#   8. DEEP reminder uses JSON sentinels and routes risky ACTIONs to proposals
#   9. Stop × low override (NIBLET_DEEP_THRESHOLD=3) DOES create PENDING_DEEP
#      (safety net works for marathon sessions)
#   10. Parallel sessions don't cross-contaminate
#   11. .gitignore add is idempotent

set -e

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$PLUGIN_DIR/hooks"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAIL=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
title() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# Build a fake hook event with realistic tool_input/tool_response that
# would expose secrets if observe.sh ever captured raw content.
event_read() {
  local session="$1" cwd="$2" path="$3"
  printf '{"session_id":"%s","tool_name":"Read","cwd":"%s","tool_input":{"file_path":"%s"},"tool_response":"SECRET_API_KEY=super-secret-do-not-store\\nOPENAI_KEY=sk-abc123"}' \
    "$session" "$cwd" "$path"
}
event_bash() {
  local session="$1" cwd="$2"
  printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","tool_input":{"command":"echo $SECRET_TOKEN_THAT_MUST_NOT_BE_LOGGED"},"tool_response":{"exit_code":0,"is_error":false,"stdout":"super-secret-token-leak"}}' \
    "$session" "$cwd"
}
event_stop() {
  local session="$1" cwd="$2"
  printf '{"session_id":"%s","cwd":"%s"}' "$session" "$cwd"
}

# Fresh git project
PROJECT="$TMP/project"
mkdir -p "$PROJECT"
( cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t \
   && echo "# test" > README.md && git add . && git commit -qm "init" )

SESSION="alpha-$(date +%s)"
STORE="$PROJECT/.niblet"
SESSION_DIR="$STORE/sessions/$SESSION"

title "1. observe.sh auto-init on first tool call"
event_read "$SESSION" "$PROJECT" "$PROJECT/src/foo.ts" | "$HOOKS/observe.sh" post >/dev/null
[ -d "$STORE/raw" ]      && pass ".niblet/raw exists"      || fail "no raw"
[ -d "$STORE/sessions" ] && pass ".niblet/sessions exists" || fail "no sessions dir"
grep -qxF ".niblet/" "$PROJECT/.gitignore" \
  && pass ".gitignore contains .niblet/" || fail "no gitignore entry"

title "2. observe.sh writes SANITIZED JSONL (no content from tool_input/tool_response)"
RAW="$STORE/raw/${SESSION}.jsonl"
[ -s "$RAW" ] && pass "raw log non-empty" || fail "raw log empty"
grep -q '"tool":"Read"' "$RAW" && pass "tool name recorded" || fail "tool name missing"
grep -q '"path":"src/foo.ts"' "$RAW" \
  && pass "safe path recorded (project-relative)" \
  || fail "path missing or absolute: $(cat "$RAW")"
# Critical security checks: secrets from tool_response and tool_input MUST NOT appear
if grep -qE "SECRET_API_KEY|sk-abc123|OPENAI_KEY" "$RAW"; then
  fail "RAW LOG CONTAINS SECRETS FROM tool_response (security regression!)"
else
  pass "no tool_response content leaked to raw log"
fi
# Now post a Bash event with secret in tool_input.command
event_bash "$SESSION" "$PROJECT" | "$HOOKS/observe.sh" post >/dev/null
if grep -q "SECRET_TOKEN_THAT_MUST_NOT_BE_LOGGED\|super-secret-token-leak" "$RAW"; then
  fail "RAW LOG CONTAINS SECRETS FROM tool_input.command or stdout (security regression!)"
else
  pass "no tool_input.command / stdout leaked to raw log"
fi
grep -q '"tool":"Bash"' "$RAW" && pass "Bash tool recorded (sans args)" \
  || fail "Bash event not recorded"

# --- Fresh project, no observe → text-only session via on_stop ---
PROJECT2="$TMP/project2"
mkdir -p "$PROJECT2"
( cd "$PROJECT2" && git init -q && git config user.email t@t && git config user.name t \
   && echo "# t" > README.md && git add . && git commit -qm "init" )
SESSION2="text-only-$(date +%s)"

title "3. on_stop.sh works on text-only session — store + gitignore appear"
[ ! -d "$PROJECT2/.niblet" ] && pass "no .niblet/ before Stop" || fail "store exists pre-stop"
event_stop "$SESSION2" "$PROJECT2" | "$HOOKS/on_stop.sh" >/dev/null
[ -d "$PROJECT2/.niblet/sessions/$SESSION2" ] \
  && pass "session dir created from on_stop alone" || fail "no session dir"
grep -qxF ".niblet/" "$PROJECT2/.gitignore" \
  && pass ".gitignore added by on_stop.sh (no prior observe)" \
  || fail ".gitignore NOT added — P1.2 regression"

title "4. on_stop creates per-session PENDING_FAST + counter"
event_stop "$SESSION" "$PROJECT" | "$HOOKS/on_stop.sh" >/dev/null
[ -f "$SESSION_DIR/PENDING_FAST" ] && pass "PENDING_FAST exists" \
  || fail "no PENDING_FAST after Stop"
[ "$(cat "$SESSION_DIR/task_counter" 2>/dev/null)" = "1" ] \
  && pass "counter=1 after one Stop" \
  || fail "counter wrong: $(cat "$SESSION_DIR/task_counter" 2>/dev/null)"

title "5. on_prompt_submit emits FAST reminder for THIS session"
OUT="$(event_stop "$SESSION" "$PROJECT" | "$HOOKS/on_prompt_submit.sh")"
echo "$OUT" | grep -q "NIBLET CHECKPOINT (fast)" \
  && pass "FAST reminder emitted" || fail "no FAST reminder"
echo "$OUT" | grep -q "session $SESSION" \
  && pass "reminder mentions session id" || fail "no session id in reminder"
echo "$OUT" | grep -q "DO NOT create skills" \
  && pass "FAST tells agent NOT to create skills (proposals only via DEEP)" \
  || fail "FAST reminder doesn't restrict skill creation"

title "6. Stop ×5 does NOT trigger DEEP (default threshold 20)"
# Reset
rm -rf "$SESSION_DIR"
for i in 1 2 3 4 5; do
  event_stop "$SESSION" "$PROJECT" | "$HOOKS/on_stop.sh" >/dev/null
done
COUNT="$(cat "$SESSION_DIR/task_counter")"
[ "$COUNT" = "5" ] && pass "counter=5 after 5 Stops" || fail "counter=$COUNT"
if [ -f "$SESSION_DIR/PENDING_DEEP" ]; then
  fail "PENDING_DEEP triggered at 5 (P2.4 regression — should require 20 or SessionEnd)"
else
  pass "no PENDING_DEEP at 5 turns — mid-session UX preserved"
fi

title "7. on_session_end.sh unconditionally creates PENDING_DEEP"
rm -f "$SESSION_DIR/PENDING_DEEP"
event_stop "$SESSION" "$PROJECT" | "$HOOKS/on_session_end.sh" >/dev/null
[ -f "$SESSION_DIR/PENDING_DEEP" ] && pass "PENDING_DEEP created by SessionEnd" \
  || fail "SessionEnd did not create PENDING_DEEP"

title "8. DEEP reminder routes risky ACTIONs to proposals"
OUT="$(event_stop "$SESSION" "$PROJECT" | "$HOOKS/on_prompt_submit.sh")"
echo "$OUT" | grep -q "NIBLET CHECKPOINT (deep)" \
  && pass "DEEP reminder emitted" || fail "no DEEP reminder"
echo "$OUT" | grep -q "<<<NIBLET ACTIONS BEGIN>>>" \
  && pass "JSON sentinel BEGIN present" || fail "no sentinel BEGIN"
echo "$OUT" | grep -q "<<<NIBLET ACTIONS END>>>" \
  && pass "JSON sentinel END present"   || fail "no sentinel END"
echo "$OUT" | grep -qF ".niblet/proposals" \
  && pass "DEEP reminder names .niblet/proposals dir" \
  || fail "proposals dir not mentioned"
echo "$OUT" | grep -qE "proposal — embed" \
  && pass "routing table marks CREATE_SKILL etc as proposal" \
  || fail "routing table missing proposal routing"
echo "$OUT" | grep -q "ADD_KB_ENTRY    project" \
  && pass "ADD_KB_ENTRY routes to live KB (auto-write tier)" \
  || fail "ADD_KB_ENTRY routing missing or wrong"

title "9. Override threshold via NIBLET_DEEP_THRESHOLD safety net"
SESSION3="marathon-$(date +%s)"
SESSION3_DIR="$STORE/sessions/$SESSION3"
export NIBLET_DEEP_THRESHOLD=3
for i in 1 2 3; do
  event_stop "$SESSION3" "$PROJECT" | "$HOOKS/on_stop.sh" >/dev/null
done
unset NIBLET_DEEP_THRESHOLD
[ -f "$SESSION3_DIR/PENDING_DEEP" ] \
  && pass "low threshold (3) triggered safety-net DEEP" \
  || fail "safety net did not fire at threshold=3"

title "10. Per-session isolation — parallel sessions don't cross-contaminate"
SESSION_B="beta-$(date +%s)"
event_stop "$SESSION_B" "$PROJECT" | "$HOOKS/on_stop.sh" >/dev/null
B_DIR="$STORE/sessions/$SESSION_B"
[ -f "$B_DIR/PENDING_FAST" ] && pass "session B has its own PENDING_FAST" \
  || fail "session B marker missing"
[ "$(cat "$B_DIR/task_counter" 2>/dev/null)" = "1" ] \
  && pass "session B counter=1 (independent from A)" \
  || fail "session B counter contaminated"
# A has PENDING_DEEP from earlier — B should NOT see it
OUT_B="$(event_stop "$SESSION_B" "$PROJECT" | "$HOOKS/on_prompt_submit.sh")"
if echo "$OUT_B" | grep -q "NIBLET CHECKPOINT (deep)"; then
  fail "session B saw session A's DEEP marker (isolation broken)"
else
  pass "session B does NOT see session A's DEEP marker"
fi
echo "$OUT_B" | grep -q "NIBLET CHECKPOINT (fast)" \
  && pass "session B sees its own FAST marker" || fail "session B FAST missing"

title "11. .gitignore add is idempotent"
LINES_BEFORE="$(grep -cxF ".niblet/" "$PROJECT/.gitignore")"
event_read "$SESSION" "$PROJECT" "$PROJECT/x.ts" | "$HOOKS/observe.sh" post >/dev/null
event_stop "$SESSION" "$PROJECT" | "$HOOKS/on_stop.sh"  >/dev/null
LINES_AFTER="$(grep -cxF ".niblet/" "$PROJECT/.gitignore")"
[ "$LINES_BEFORE" = "$LINES_AFTER" ] \
  && pass "no duplicate gitignore entries (lines=$LINES_AFTER)" \
  || fail "duplicates added: $LINES_BEFORE → $LINES_AFTER"

printf '\n'
if [ "$FAIL" = "0" ]; then
  printf '\033[32mAll checks passed.\033[0m\n'
  exit 0
else
  printf '\033[31m%d check(s) failed.\033[0m\n' "$FAIL"
  exit 1
fi
