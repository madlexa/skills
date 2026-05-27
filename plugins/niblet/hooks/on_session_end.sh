#!/usr/bin/env bash
# on_session_end.sh — fires on SessionEnd (session terminates).
#
# Touches PENDING_DEEP for THIS session. The user's next session in this
# project will see the marker (via on_prompt_submit.sh) and trigger a
# sub-agent pass that processes the just-finished session's raw log.
#
# This is the natural moment for DEEP work: the user is not waiting,
# the session is fully observable, and we don't interrupt mid-session UX.

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
niblet_ensure_store "$PROJECT_ROOT" "$SESSION" >/dev/null
SESSION_DIR="$(niblet_session_dir "$PROJECT_ROOT" "$SESSION")"
[ -n "$SESSION_DIR" ] || exit 0

touch "$SESSION_DIR/PENDING_DEEP" 2>/dev/null
exit 0
