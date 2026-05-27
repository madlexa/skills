#!/usr/bin/env bash
# observe.sh — PreToolUse/PostToolUse logger.
#
# Reads hook event JSON from stdin (Claude Code / Kimi format).
# Auto-initializes <project>/.niblet/ on first run.
# Appends one JSONL event per call to raw/<session>.jsonl.
#
# Never fails or writes to stderr. Hooks must be invisible to the agent
# unless they intentionally inject reminders.
#
# Argv:
#   $1 — phase: "pre" or "post" (set by hook registration in settings)

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/../lib/paths.sh"   2>/dev/null || exit 0
. "$SCRIPT_DIR/../lib/gitignore.sh" 2>/dev/null || exit 0
. "$SCRIPT_DIR/../lib/jsonl.sh"   2>/dev/null || exit 0

PHASE="${1:-post}"
INPUT="$(cat 2>/dev/null || true)"

# --- Parse stdin (with jq if present, crude fallback otherwise) ---
have_jq=0; command -v jq >/dev/null 2>&1 && have_jq=1

field() {
  local key="$1"
  if [ "$have_jq" = 1 ]; then
    printf '%s' "$INPUT" | jq -r ".${key} // empty" 2>/dev/null
  else
    printf '%s' "$INPUT" | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
  fi
}

CWD="$(field cwd)"
[ -z "$CWD" ] && CWD="$PWD"
SESSION="$(field session_id)"
[ -z "$SESSION" ] && SESSION="unknown"
TOOL="$(field tool_name)"
[ -z "$TOOL" ] && TOOL="unknown"

# --- Project root + auto-init store ---
PROJECT_ROOT="$(niblet_project_root "$CWD")"
STORE="$(niblet_store "$PROJECT_ROOT")"

if [ ! -d "$STORE" ]; then
  mkdir -p "$STORE/raw" "$STORE/log" 2>/dev/null || exit 0
  # Auto-add to .gitignore if this is a git repo
  if [ -d "$PROJECT_ROOT/.git" ] || ( cd "$PROJECT_ROOT" 2>/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1 ); then
    gitignore_add "$PROJECT_ROOT" ".niblet/"
  fi
fi

# --- Extract tool_input / tool_response as compact JSON ---
ARGS_JSON='""'
RESULT_TEXT=""
if [ "$have_jq" = 1 ]; then
  ARGS_JSON="$(printf '%s' "$INPUT" | jq -c '.tool_input // ""' 2>/dev/null)"
  [ -z "$ARGS_JSON" ] && ARGS_JSON='""'
  if [ "$PHASE" = "post" ]; then
    RESULT_TEXT="$(printf '%s' "$INPUT" | jq -r '.tool_response // ""' 2>/dev/null | head -c 2000)"
  fi
fi

# --- Append event ---
RAW_FILE="$STORE/raw/${SESSION}.jsonl"
EVENT="$(jsonl_observe_event "$SESSION" "$PHASE" "$TOOL" "$ARGS_JSON" "$RESULT_TEXT")"
jsonl_append "$RAW_FILE" "$EVENT"

# Hooks must exit 0 silently
exit 0
