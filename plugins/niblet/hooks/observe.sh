#!/usr/bin/env bash
# observe.sh — PreToolUse / PostToolUse logger (sanitized).
#
# The plugin MUST NOT capture raw tool_input or tool_response. Those can
# contain secrets (env vars, .env contents, API tokens) and untrusted text
# that would become persistent prompt injection when read back by the
# niblet-deep sub-agent and turned into committed skills.
#
# We log only what is needed to reconstruct WORKFLOW PATTERNS:
#   - timestamp
#   - session id
#   - phase (pre/post)
#   - tool name
#   - safe file path (Read/Edit/Write/MultiEdit/NotebookEdit/Glob/Grep)
#   - exit_code (for Bash)
#   - success (bool)
#
# Path is rewritten to project-relative when possible. Bash command args
# are deliberately omitted.

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/../lib/store.sh"    2>/dev/null || exit 0
. "$SCRIPT_DIR/../lib/sanitize.sh" 2>/dev/null || exit 0
. "$SCRIPT_DIR/../lib/jsonl.sh"    2>/dev/null || exit 0

PHASE="${1:-post}"
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
TOOL="$(field tool_name)";     [ -z "$TOOL" ]    && TOOL="unknown"

PROJECT_ROOT="$(niblet_project_root "$CWD")"
STORE="$(niblet_ensure_store "$PROJECT_ROOT" "$SESSION")"
[ -n "$STORE" ] || exit 0

# Extract sanitized tool_input (only safe path, no content).
TOOL_INPUT='""'
SAFE_PATH=""
if [ "$have_jq" = 1 ]; then
  TOOL_INPUT="$(printf '%s' "$INPUT" | jq -c '.tool_input // ""' 2>/dev/null)"
  [ -z "$TOOL_INPUT" ] && TOOL_INPUT='""'
  SAFE_PATH="$(niblet_safe_path "$TOOL" "$TOOL_INPUT")"
  SAFE_PATH="$(niblet_project_relative_path "$PROJECT_ROOT" "$SAFE_PATH")"
fi

# Extract sanitized tool_response (only exit code + success bool, no content).
EXIT_CODE=""
SUCCESS="true"
if [ "$PHASE" = "post" ] && [ "$have_jq" = 1 ]; then
  TOOL_RESPONSE="$(printf '%s' "$INPUT" | jq -c '.tool_response // ""' 2>/dev/null)"
  EXIT_CODE="$(niblet_safe_exit_code "$TOOL_RESPONSE")"
  SUCCESS="$(niblet_safe_success "$TOOL_RESPONSE")"
fi

# Build event JSON manually (no tool_input/tool_response content ever).
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EVENT="$(printf '{"ts":"%s","session":"%s","phase":"%s","tool":"%s","path":"%s","exit_code":"%s","success":%s}' \
  "$TS" \
  "$(jsonl_escape "$SESSION")" \
  "$(jsonl_escape "$PHASE")" \
  "$(jsonl_escape "$TOOL")" \
  "$(jsonl_escape "$SAFE_PATH")" \
  "$(jsonl_escape "$EXIT_CODE")" \
  "$SUCCESS")"

RAW_FILE="$STORE/raw/${SESSION}.jsonl"
jsonl_append "$RAW_FILE" "$EVENT"

exit 0
