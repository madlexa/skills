#!/usr/bin/env bash
# on_stop.sh — fires on Stop (end of every main-agent turn).
#
# Per-turn lifecycle:
#   - Ensure store and per-session subdir exist (idempotent).
#   - Touch PENDING_FAST for THIS session.
#   - Increment THIS session's task counter.
#   - SAFETY NET ONLY: if counter ≥ NIBLET_DEEP_THRESHOLD (default 20) also
#     touch PENDING_DEEP. This is meant for marathon sessions where the
#     SessionEnd event never fires. Normal sessions get their DEEP pass
#     from on_session_end.sh, not from this threshold.
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
SESSION_DIR="$(niblet_session_dir "$PROJECT_ROOT" "$SESSION")"
[ -n "$SESSION_DIR" ] || exit 0

# Per-turn FAST checkpoint (always).
touch "$SESSION_DIR/PENDING_FAST" 2>/dev/null

# Per-session counter.
COUNTER_FILE="$SESSION_DIR/task_counter"
COUNT=0
[ -f "$COUNTER_FILE" ] && COUNT="$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)"
COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$COUNTER_FILE" 2>/dev/null

# DEEP only on safety-net threshold for marathon sessions. Normal DEEP
# triggering is on_session_end.sh.
if [ "$COUNT" -ge "$DEEP_THRESHOLD" ]; then
  touch "$SESSION_DIR/PENDING_DEEP" 2>/dev/null
fi

exit 0
