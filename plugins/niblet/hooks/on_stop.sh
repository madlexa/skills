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

# Per-turn FAST checkpoint, gated on real file mutations.
# Touching PENDING_FAST every turn means a FAST checkpoint is always pending and
# fires mid-task on the next prompt. Only mark it when this turn actually changed
# project files (Edit/Write/MultiEdit/NotebookEdit in the raw log). Track the count
# seen so far in fast_seen and set the marker only when it grows. Without jq/raw
# log we cannot tell, so fall back to the old always-touch behavior.
# NIBLET_FAST_ON_EDIT_ONLY=0 restores unconditional per-turn marking.
RAW_LOG="$STORE/raw/${SESSION}.jsonl"
FAST_SEEN_FILE="$SESSION_DIR/fast_seen"
if [ "${NIBLET_FAST_ON_EDIT_ONLY:-1}" = "1" ] && [ "$have_jq" = "1" ] && [ -f "$RAW_LOG" ]; then
  EDITS="$(grep -cE '"phase":"post","tool":"(Edit|Write|MultiEdit|NotebookEdit)"' "$RAW_LOG" 2>/dev/null || echo 0)"
  case "$EDITS" in *[!0-9]*) EDITS=0 ;; esac
  PREV_EDITS=0
  [ -f "$FAST_SEEN_FILE" ] && PREV_EDITS="$(cat "$FAST_SEEN_FILE" 2>/dev/null || echo 0)"
  case "$PREV_EDITS" in *[!0-9]*) PREV_EDITS=0 ;; esac
  if [ "$EDITS" -gt "$PREV_EDITS" ]; then
    touch "$SESSION_DIR/PENDING_FAST" 2>/dev/null
    printf '%s' "$EDITS" > "$FAST_SEEN_FILE" 2>/dev/null
  fi
else
  # Fallback: behave as before (always mark).
  touch "$SESSION_DIR/PENDING_FAST" 2>/dev/null
fi

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
# Gate the safety-net enqueue on real work too (same signal as on_session_end.sh),
# so a long but tool-light session doesn't seed a NOTHING DEEP job.
SN_TOOLCALLS=0
[ -f "$RAW_LOG" ] && SN_TOOLCALLS="$(grep -c '"phase":"post"' "$RAW_LOG" 2>/dev/null || echo 0)"
case "$SN_TOOLCALLS" in *[!0-9]*) SN_TOOLCALLS=0 ;; esac
SN_MIN_TC="${NIBLET_DEEP_MIN_TOOLCALLS:-8}"
case "$SN_MIN_TC" in *[!0-9]*) SN_MIN_TC=8 ;; esac

if [ "$COUNT" -ge "$DEEP_THRESHOLD" ] && [ "$SN_TOOLCALLS" -ge "$SN_MIN_TC" ]; then
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
