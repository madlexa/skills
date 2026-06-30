#!/usr/bin/env bash
# capture_task_test.sh — contract tests for niblet-capture-task.
set -e

PROJECT_ROOT="/Users/Aleksey.Dobrynin/projects/madlexa/skills"
SCRIPT="$PROJECT_ROOT/plugins/niblet/bin/niblet-capture-task"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

# Capture a success task.
"$SCRIPT" \
  --project-root "$TMP" \
  --session-id session-1 \
  --summary "Test task" \
  --components niblet-core,niblet-status \
  --skills niblet,test-driven-development \
  --files-modified plugins/niblet/bin/niblet-status \
  --outcome success >/dev/null || fail "success capture failed"

[ -f "$TMP/.niblet/tasks/session-1.jsonl" ] || fail "task record not written"
[ -f "$TMP/.niblet/metrics/skills.jsonl" ] || fail "skill metrics not written"

# Verify metrics contain both skills with success=true.
grep -q '"skill"[[:space:]]*:[[:space:]]*"niblet"' "$TMP/.niblet/metrics/skills.jsonl" || fail "niblet metric missing"
grep -q '"skill"[[:space:]]*:[[:space:]]*"test-driven-development"' "$TMP/.niblet/metrics/skills.jsonl" || fail "tdd metric missing"
grep -q '"success"[[:space:]]*:[[:space:]]*true' "$TMP/.niblet/metrics/skills.jsonl" || fail "success should be true"

# Capture negative feedback should write memory.
"$SCRIPT" \
  --project-root "$TMP" \
  --session-id session-2 \
  --summary "Failed task" \
  --outcome failure \
  --feedback "Never touch CLAUDE.md directly" >/dev/null || fail "failure capture failed"

[ -f "$TMP/.claude/memory/feedback_task.md" ] || fail "feedback memory not written"
grep -q "Never touch CLAUDE.md directly" "$TMP/.claude/memory/feedback_task.md" || fail "feedback content missing"

# Missing project root should fail.
if "$SCRIPT" --project-root "$TMP/does-not-exist" --session-id x >/dev/null 2>&1; then
  fail "missing project root should fail"
fi

echo "capture task tests passed"
