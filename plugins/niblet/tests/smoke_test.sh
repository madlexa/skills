#!/usr/bin/env bash
# smoke_test.sh — end-to-end test of niblet v0.2.1 contract.
#
# Tests security boundary + lifecycle, not just plumbing:
#
#   1. observe.sh auto-init + sanitized capture (no tool content)
#   2. on_stop.sh per-session PENDING_FAST + counter
#   3. on_prompt_submit.sh FAST reminder for own session
#   4. Stop ×5 does NOT escalate to DEEP (default threshold 20)
#   5. on_session_end.sh writes a project-wide queue entry
#   6. DEEP reminder reaches a NEW session id (cross-session delivery)
#   7. Safety-net at low threshold writes queue entry, resets counter
#   8. niblet-apply rejects path traversal in topic → proposal, CLAUDE.md untouched
#   9. niblet-apply rejects path traversal in name (CREATE_SKILL)
#   10. niblet-apply auto-writes ADD_KB_ENTRY when slug is valid
#   11. niblet-apply routes CREATE_SKILL to proposal even with valid slug
#   12. niblet-promote on CREATE_SKILL proposal yields a SKILL.md with ONE frontmatter
#   13. niblet-promote on UPDATE_CLAUDE proposal APPENDS, does not replace
#   14. on_session_start.sh emits KB index naming each topic

set -e

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$PLUGIN_DIR/hooks"
BIN="$PLUGIN_DIR/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAIL=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
title() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# Hook event helpers
event_read_with_secret() {
  local session="$1" cwd="$2" path="$3"
  jq -nc --arg s "$session" --arg c "$cwd" --arg p "$path" \
    '{session_id:$s, tool_name:"Read", cwd:$c, tool_input:{file_path:$p}, tool_response:"SECRET_API_KEY=super-secret\nOPENAI_KEY=sk-abc123"}'
}
event_bash_with_secret() {
  local session="$1" cwd="$2"
  jq -nc --arg s "$session" --arg c "$cwd" \
    '{session_id:$s, tool_name:"Bash", cwd:$c, tool_input:{command:"echo $LEAK_TOKEN"}, tool_response:{exit_code:0, is_error:false, stdout:"super-secret-stdout-leak"}}'
}
event_stop() {
  local session="$1" cwd="$2"
  jq -nc --arg s "$session" --arg c "$cwd" '{session_id:$s, cwd:$c}'
}

# Build action JSON safely via jq
action_kb() {
  local topic="$1" content="$2"
  jq -nc --arg t "$topic" --arg c "$content" \
    '{action:"ADD_KB_ENTRY", scope:"project", topic:$t, content:$c}'
}
action_skill() {
  local name="$1" content="$2"
  jq -nc --arg n "$name" --arg c "$content" \
    '{action:"CREATE_SKILL", scope:"project", name:$n, content:$c}'
}
action_update_claude() {
  local section="$1" addition="$2"
  jq -nc --arg s "$section" --arg a "$addition" \
    '{action:"UPDATE_CLAUDE", scope:"project", section:$s, addition:$a}'
}

# Fresh git project
PROJECT="$TMP/project"
mkdir -p "$PROJECT"
( cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t \
   && echo "# test" > README.md && git add . && git commit -qm "init" )

SESSION_A="alpha-$(date +%s)"
STORE="$PROJECT/.niblet"
A_DIR="$STORE/sessions/$SESSION_A"

title "1. observe.sh — sanitized capture (no tool content)"
event_read_with_secret "$SESSION_A" "$PROJECT" "$PROJECT/src/foo.ts" | "$HOOKS/observe.sh" post >/dev/null
event_bash_with_secret "$SESSION_A" "$PROJECT" | "$HOOKS/observe.sh" post >/dev/null
[ -d "$STORE/raw" ] && pass "raw dir created" || fail "no raw dir"
RAW="$STORE/raw/${SESSION_A}.jsonl"
[ -s "$RAW" ] && pass "raw log non-empty" || fail "raw log empty"
grep -q '"path":"src/foo.ts"' "$RAW" && pass "project-relative path recorded" \
  || fail "path missing or absolute: $(cat "$RAW")"
if grep -qE "SECRET_API_KEY|sk-abc123|OPENAI_KEY|LEAK_TOKEN|super-secret" "$RAW"; then
  fail "SECRETS LEAKED to raw log (security regression!)"
else
  pass "no secrets leaked from tool_input/tool_response"
fi
grep -qxF ".niblet/" "$PROJECT/.gitignore" && pass ".gitignore auto-added" || fail "no gitignore"

title "2. on_stop.sh per-session PENDING_FAST + counter"
event_stop "$SESSION_A" "$PROJECT" | "$HOOKS/on_stop.sh" >/dev/null
[ -f "$A_DIR/PENDING_FAST" ] && pass "PENDING_FAST per-session" || fail "no PENDING_FAST"
[ "$(cat "$A_DIR/task_counter")" = "1" ] && pass "counter=1" || fail "counter wrong"

title "3. on_prompt_submit FAST reminder mentions niblet-apply"
OUT="$(event_stop "$SESSION_A" "$PROJECT" | "$HOOKS/on_prompt_submit.sh")"
echo "$OUT" | grep -q "NIBLET CHECKPOINT (fast)" && pass "FAST emitted" || fail "no FAST"
echo "$OUT" | grep -q "niblet-apply" \
  && pass "FAST instructs niblet-apply (not direct Edit/Write)" \
  || fail "FAST missing niblet-apply instruction"

title "4. Stop ×5 does NOT escalate to DEEP (default threshold 20)"
rm -rf "$A_DIR"
for i in 1 2 3 4 5; do
  event_stop "$SESSION_A" "$PROJECT" | "$HOOKS/on_stop.sh" >/dev/null
done
[ "$(cat "$A_DIR/task_counter")" = "5" ] && pass "counter=5" || fail "counter wrong"
QUEUE_COUNT="$(find "$STORE/pending_deep" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$QUEUE_COUNT" = "0" ] && pass "no DEEP queue entry at 5 turns" \
  || fail "DEEP queue grew unexpectedly: $QUEUE_COUNT"

title "5. on_session_end writes a project-wide queue entry"
event_stop "$SESSION_A" "$PROJECT" | "$HOOKS/on_session_end.sh" >/dev/null
QUEUE_COUNT="$(find "$STORE/pending_deep" -maxdepth 1 -type f -name '*.queue' 2>/dev/null | wc -l | tr -d ' ')"
[ "$QUEUE_COUNT" -ge "1" ] && pass "queue entry created" || fail "no queue file"
QUEUE_FILE="$(ls -1 "$STORE/pending_deep"/*.queue | head -n1)"
grep -q "session_id=$SESSION_A" "$QUEUE_FILE" && pass "queue names ended session A" \
  || fail "queue file does not name session A"
grep -q "raw_log=.*${SESSION_A}\.jsonl" "$QUEUE_FILE" && pass "queue points to A's raw log" \
  || fail "queue raw_log missing"

title "6. DEEP reminder reaches a NEW session id (cross-session delivery)"
SESSION_B="bravo-$(date +%s)"
OUT_B="$(event_stop "$SESSION_B" "$PROJECT" | "$HOOKS/on_prompt_submit.sh")"
echo "$OUT_B" | grep -q "NIBLET CHECKPOINT (deep)" \
  && pass "DEEP delivered to new session B (cross-session works)" \
  || fail "DEEP NOT delivered to new session — P0 #1 regression"
echo "$OUT_B" | grep -q "$SESSION_A" \
  && pass "DEEP reminder names ended session A" || fail "session A not named"
echo "$OUT_B" | grep -q "<<<NIBLET ACTIONS BEGIN>>>" \
  && pass "JSON sentinel BEGIN present" || fail "no sentinel"
echo "$OUT_B" | grep -q "niblet-apply" \
  && pass "DEEP instructs niblet-apply for each ACTION" \
  || fail "DEEP missing niblet-apply"
QUEUE_BASE="$(basename "$QUEUE_FILE")"
echo "$OUT_B" | grep -qE "rm .*$QUEUE_BASE" \
  && pass "DEEP names the queue file to delete (rm <…>/$QUEUE_BASE)" \
  || fail "no queue rm hint for $QUEUE_BASE"

title "7. Safety-net writes queue entry, resets counter"
SESSION_C="marathon-$(date +%s)"
export NIBLET_DEEP_THRESHOLD=3
for i in 1 2 3; do
  event_stop "$SESSION_C" "$PROJECT" | "$HOOKS/on_stop.sh" >/dev/null
done
unset NIBLET_DEEP_THRESHOLD
QC="$(find "$STORE/pending_deep" -maxdepth 1 -type f -name "*${SESSION_C}*.queue" 2>/dev/null | wc -l | tr -d ' ')"
[ "$QC" -ge "1" ] && pass "safety-net queue entry created at threshold=3" \
  || fail "safety-net did not write queue"
[ "$(cat "$STORE/sessions/$SESSION_C/task_counter" 2>/dev/null)" = "0" ] \
  && pass "counter reset after safety-net fire" \
  || fail "counter not reset: $(cat "$STORE/sessions/$SESSION_C/task_counter" 2>/dev/null)"

title "8. niblet-apply: path traversal in topic → proposal, CLAUDE.md untouched"
[ ! -f "$PROJECT/CLAUDE.md" ] || rm "$PROJECT/CLAUDE.md"
RES="$(action_kb "../../CLAUDE.md" "PWNED-CONTENT" | "$BIN/niblet-apply" --project-root "$PROJECT")"
echo "$RES" | grep -q "^proposal:" && pass "path traversal lands in proposal" \
  || fail "should have been proposal: $RES"
[ ! -f "$PROJECT/CLAUDE.md" ] && pass "CLAUDE.md not created (no write to live tree)" \
  || fail "CLAUDE.md was created — security regression!"
PROPOSAL_FILE="$(ls -t "$STORE/proposals"/*.md 2>/dev/null | head -n1)"
# Path-traversal topic fails slug regex (because of '/' and '..') BEFORE the
# containment check — so the proposal carries invalid-slug. That is still
# rejection; either reason proves the action was diverted from auto-write.
grep -qE 'rejected_reason: (invalid-slug|path-escape)' "$PROPOSAL_FILE" \
  && pass "proposal carries rejected_reason (invalid-slug or path-escape)" \
  || fail "no rejected_reason in $PROPOSAL_FILE"

title "9. niblet-apply: invalid slug in CREATE_SKILL → proposal"
RES="$(action_skill "foo/bar" "---\nname: x\n---\nbody" | "$BIN/niblet-apply" --project-root "$PROJECT")"
echo "$RES" | grep -q "^proposal:" && pass "slug with '/' → proposal" \
  || fail "should have been proposal"
PROPOSAL_FILE="$(ls -t "$STORE/proposals"/*.md 2>/dev/null | head -n1)"
grep -q 'rejected_reason: invalid-slug' "$PROPOSAL_FILE" \
  && pass "proposal carries rejected_reason=invalid-slug" \
  || fail "missing rejected_reason invalid-slug"

title "10. niblet-apply: valid slug ADD_KB_ENTRY auto-writes"
RES="$(action_kb "auth.md" "# Auth body" | "$BIN/niblet-apply" --project-root "$PROJECT")"
echo "$RES" | grep -q "^applied:" && pass "auto-write applied" || fail "should have been applied"
[ -f "$PROJECT/.claude/kb/auth.md" ] && pass "KB file written to live tree" \
  || fail "KB file missing"

title "11. niblet-apply: valid-slug CREATE_SKILL still goes to proposal"
RES="$(action_skill "my-skill" "$(printf -- '---\nname: my-skill\ndescription: test\n---\nbody here')" \
  | "$BIN/niblet-apply" --project-root "$PROJECT")"
echo "$RES" | grep -q "^proposal:" && pass "CREATE_SKILL is proposal tier even with valid slug" \
  || fail "should have been proposal"
# Among CREATE_SKILL proposals, pick one with a target field (the valid-slug
# proposal from test 11), not the invalid-slug rejection from test 9.
SKILL_PROPOSAL=""
for f in $(grep -rl 'action: CREATE_SKILL' "$STORE/proposals" 2>/dev/null); do
  if grep -q '^target:' "$f"; then
    SKILL_PROPOSAL="$f"
    break
  fi
done
[ -n "$SKILL_PROPOSAL" ] && pass "CREATE_SKILL proposal with target located" \
  || fail "could not locate CREATE_SKILL proposal with target field"

title "12. niblet-promote CREATE_SKILL → single-frontmatter SKILL.md"
( cd "$PROJECT" && "$BIN/niblet-promote" "$SKILL_PROPOSAL" >/dev/null )
SKILL_FILE="$PROJECT/.claude/skills/niblet/my-skill/SKILL.md"
[ -f "$SKILL_FILE" ] && pass "skill file written at expected path" || fail "skill not at $SKILL_FILE"
# Count "---" separators — payload had exactly one frontmatter (open + close = two ---)
fm_count="$(grep -c '^---$' "$SKILL_FILE" 2>/dev/null || echo 0)"
[ "$fm_count" = "2" ] && pass "exactly one frontmatter block (2 separators) in promoted skill" \
  || fail "frontmatter count wrong: $fm_count (envelope leaked into payload)"
head -n1 "$SKILL_FILE" | grep -q '^---$' && pass "file starts with frontmatter open" \
  || fail "first line not ---"
sed -n '2p' "$SKILL_FILE" | grep -q '^name:' && pass "first metadata key is 'name:'" \
  || fail "frontmatter not the payload's: $(sed -n '2p' "$SKILL_FILE")"

title "13. niblet-promote UPDATE_CLAUDE → append, not replace"
echo "# Project Title" > "$PROJECT/CLAUDE.md"
echo "" >> "$PROJECT/CLAUDE.md"
echo "## Conventions" >> "$PROJECT/CLAUDE.md"
echo "Existing rule." >> "$PROJECT/CLAUDE.md"
# Stage an UPDATE_CLAUDE proposal
action_update_claude "Conventions" "Newly noted rule." | "$BIN/niblet-apply" --project-root "$PROJECT" >/dev/null
UC_PROPOSAL="$(grep -rl 'action: UPDATE_CLAUDE' "$STORE/proposals" 2>/dev/null | head -n1)"
[ -n "$UC_PROPOSAL" ] && pass "UPDATE_CLAUDE proposal staged" || fail "no UPDATE_CLAUDE proposal"
( cd "$PROJECT" && "$BIN/niblet-promote" "$UC_PROPOSAL" >/dev/null )
grep -q "Existing rule." "$PROJECT/CLAUDE.md" && pass "existing CLAUDE.md content preserved" \
  || fail "promote DELETED existing CLAUDE.md content — P1 regression!"
grep -q "Newly noted rule." "$PROJECT/CLAUDE.md" && pass "new addition appended" \
  || fail "addition missing"
grep -q "^# Project Title$" "$PROJECT/CLAUDE.md" && pass "title preserved" \
  || fail "title lost"

title "14. on_session_start emits KB index"
# Drop a few KB entries (auth.md already there from #10)
mkdir -p "$PROJECT/.claude/kb"
cat > "$PROJECT/.claude/kb/db-schema.md" <<EOF
# Database schema
Postgres with three schemas: public, auth, billing.
EOF
OUT="$(event_stop "starter-$(date +%s)" "$PROJECT" | "$HOOKS/on_session_start.sh")"
echo "$OUT" | grep -q "NIBLET KB index" && pass "index header emitted" \
  || fail "no header"
echo "$OUT" | grep -q "auth.md" && pass "auth.md listed" || fail "auth.md missing"
echo "$OUT" | grep -q "db-schema.md" && pass "db-schema.md listed" || fail "db-schema.md missing"
echo "$OUT" | grep -q "Database schema" && pass "H1 blurb included" || fail "no H1 blurb"

printf '\n'
if [ "$FAIL" = "0" ]; then
  printf '\033[32mAll checks passed.\033[0m\n'
  exit 0
else
  printf '\033[31m%d check(s) failed.\033[0m\n' "$FAIL"
  exit 1
fi
