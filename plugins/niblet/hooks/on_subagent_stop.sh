#!/usr/bin/env bash
# on_subagent_stop.sh — fires on SubagentStop event.
#
# Marks PENDING_FAST so the next UserPromptSubmit injects a FAST CRYSTALLIZE
# reminder. Also increments the task counter; when it reaches the deep threshold
# (default 5), additionally marks PENDING_DEEP for a sub-agent crystallization pass.

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/../lib/paths.sh" 2>/dev/null || exit 0

DEEP_THRESHOLD="${NIBLET_DEEP_THRESHOLD:-5}"
INPUT="$(cat 2>/dev/null || true)"

CWD="$(niblet_cwd_from_stdin "$INPUT")"
[ -z "$CWD" ] && CWD="$PWD"

PROJECT_ROOT="$(niblet_project_root "$CWD")"
STORE="$(niblet_store "$PROJECT_ROOT")"
mkdir -p "$STORE" 2>/dev/null || exit 0

# Mark fast pending (always)
touch "$STORE/PENDING_FAST" 2>/dev/null

# Increment task counter and check deep threshold
COUNTER_FILE="$STORE/task_counter"
COUNT=0
[ -f "$COUNTER_FILE" ] && COUNT="$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)"
COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$COUNTER_FILE" 2>/dev/null

if [ "$COUNT" -ge "$DEEP_THRESHOLD" ]; then
  touch "$STORE/PENDING_DEEP" 2>/dev/null
fi

exit 0
