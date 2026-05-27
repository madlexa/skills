#!/usr/bin/env bash
# on_stop.sh — fires on Stop (end of every main-agent turn).
#
# Per-turn lifecycle:
#   - Ensure store and per-session subdir exist (idempotent).
#   - Touch PENDING_FAST for THIS session.
#   - Increment THIS session's task counter.
#   - SAFETY NET ONLY: if counter ≥ NIBLET_DEEP_THRESHOLD (default 20),
#     write a queue file to <store>/pending_deep/ and reset the counter.
#     This is meant for marathon sessions where SessionEnd never fires.
#     Normal sessions get their DEEP pass from on_session_end.sh.
#
# Per-session paths guarantee parallel sessions don't clobber each other.

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/../lib/store.sh" 2>/dev/null || exit 0

DEEP_THRESHOLD="${NIBLET_DEEP_THRESHOLD:-20}"
INPUT="$(cat 2>/dev/null || true)"

have_jq=0; command -v jq >/dev/null 2>&1 && have_jq=1
field() {
  local key="$1"
  if [ "$have_jq" = 1 ]; then
    printf '%s' "$INPUT" | jq -r ".${key} // empty" 2>/dev/null
  else
    printf '%s' "$INPUT" | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
  fi
}

CWD="$(field cwd)";            [ -z "$CWD" ]     && CWD="$PWD"
SESSION="$(field session_id)"; [ -z "$SESSION" ] && SESSION="unknown"

PROJECT_ROOT="$(niblet_project_root "$CWD")"
niblet_ensure_store "$PROJECT_ROOT" "$SESSION" >/dev/null
STORE="$(niblet_store "$PROJECT_ROOT")"
SESSION_DIR="$(niblet_session_dir "$PROJECT_ROOT" "$SESSION")"
[ -n "$SESSION_DIR" ] || exit 0
[ -n "$STORE" ] || exit 0

# Per-turn FAST checkpoint (always).
touch "$SESSION_DIR/PENDING_FAST" 2>/dev/null

# Per-session counter.
COUNTER_FILE="$SESSION_DIR/task_counter"
COUNT=0
[ -f "$COUNTER_FILE" ] && COUNT="$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)"
COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$COUNTER_FILE" 2>/dev/null

# Safety net only: marathon sessions where SessionEnd never fires.
# Normal DEEP comes from on_session_end.sh via the project queue.
# The safety-net entry is also placed on the project queue so the
# CURRENT session can pick it up on its NEXT UserPromptSubmit.
if [ "$COUNT" -ge "$DEEP_THRESHOLD" ]; then
  QUEUE_DIR="$STORE/pending_deep"
  mkdir -p "$QUEUE_DIR" 2>/dev/null
  TS="$(date -u +%Y%m%dT%H%M%SZ)"
  QUEUE_FILE="$QUEUE_DIR/${TS}-${SESSION}-safetynet.queue"
  if [ ! -f "$QUEUE_FILE" ]; then
    {
      echo "session_id=$SESSION"
      echo "raw_log=$STORE/raw/${SESSION}.jsonl"
      echo "turns=$COUNT"
      echo "ended_at=safety-net@$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$QUEUE_FILE" 2>/dev/null
  fi
  # Reset counter so we don't emit a queue file on every subsequent turn.
  printf 0 > "$COUNTER_FILE" 2>/dev/null
fi

exit 0
