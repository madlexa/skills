#!/usr/bin/env bash
# on_session_end.sh — fires on SessionEnd (session terminates).
#
# Writes a project-wide queue file so the NEXT session in this project picks
# up the DEEP checkpoint regardless of session_id. Per-session markers are
# unreachable across sessions because UserPromptSubmit only sees its own
# session_id — that bug was the original v0.2 P0 (the marker would be
# orphaned).
#
# Queue file:
#   <project>/.niblet/pending_deep/<utc-ts>-<ended-session-id>.queue
#
# Body (newline-delimited key=value):
#   session_id=<id>
#   raw_log=<absolute path to .jsonl>
#   turns=<count>
#   ended_at=<utc iso>

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/../lib/store.sh" 2>/dev/null || exit 0

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
STORE="$(niblet_ensure_store "$PROJECT_ROOT" "$SESSION")"
[ -n "$STORE" ] || exit 0

QUEUE_DIR="$STORE/pending_deep"
mkdir -p "$QUEUE_DIR" 2>/dev/null

TS="$(date -u +%Y%m%dT%H%M%SZ)"
QUEUE_FILE="$QUEUE_DIR/${TS}-${SESSION}.queue"

# Look up turn count from per-session counter (best effort).
TURNS=0
COUNTER_FILE="$STORE/sessions/$SESSION/task_counter"
[ -f "$COUNTER_FILE" ] && TURNS="$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)"

{
  echo "session_id=$SESSION"
  echo "raw_log=$STORE/raw/${SESSION}.jsonl"
  echo "turns=$TURNS"
  echo "ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$QUEUE_FILE" 2>/dev/null

exit 0
