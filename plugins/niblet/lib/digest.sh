#!/usr/bin/env bash
# digest.sh — sanitized session digest writer.
#
# Reads the raw JSONL log for a session and writes a safe summary to
# $store/digests/<session_id>.json. The digest contains only counts and
# project-relative filenames — never raw command args, file contents, env
# vars, secrets, or any other tool_input/tool_response data.

__niblet_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$__niblet_lib_dir/paths.sh"  2>/dev/null
. "$__niblet_lib_dir/store.sh"  2>/dev/null
unset __niblet_lib_dir

# niblet_write_digest <project_root> <session_id>
#
# Reads $store/raw/<session_id>.jsonl, extracts:
#   - turn count (post-phase events)
#   - failed_commands count (Bash tool with success=false)
#   - files: unique sorted list of non-empty path values
# Writes sanitized JSON to $store/digests/<session_id>.json.
# Safe to call even when the raw log is absent (writes a minimal digest).
niblet_write_digest() {
  local project_root="$1"
  local session_id="$2"
  [ -n "$project_root" ] || return 0
  [ -n "$session_id" ]   || return 0

  local store; store="$(niblet_store "$project_root")"
  local raw="$store/raw/${session_id}.jsonl"
  local out="$store/digests/${session_id}.json"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  mkdir -p "$store/digests" 2>/dev/null

  local turns=0 failed=0 files_json="[]"

  if [ -f "$raw" ] && command -v jq >/dev/null 2>&1; then
    turns="$(jq -c 'select(.phase=="post")' "$raw" 2>/dev/null | wc -l | tr -d ' ')"
    failed="$(jq -c 'select(.tool=="Bash" and .success==false)' "$raw" 2>/dev/null | wc -l | tr -d ' ')"
    files_json="$(jq -r 'select(.path != null and .path != "") | .path' "$raw" 2>/dev/null \
      | sort -u \
      | jq -R . \
      | jq -sc . 2>/dev/null || echo '[]')"
  elif [ -f "$raw" ]; then
    # Fallback without jq: count lines as rough turn estimate, no file list
    turns="$(wc -l < "$raw" | tr -d ' ')"
  fi

  # Validate outputs are safe (numeric + JSON array only — no raw content)
  case "$turns" in *[!0-9]*) turns=0 ;; esac
  case "$failed" in *[!0-9]*) failed=0 ;; esac
  # files_json must be a JSON array; reset if not
  printf '%s' "$files_json" | jq -e 'type == "array"' >/dev/null 2>&1 || files_json="[]"

  printf '{"session_id":"%s","generated_at":"%s","turns":%s,"failed_commands":%s,"files":%s}\n' \
    "$session_id" "$ts" "$turns" "$failed" "$files_json" \
    > "$out" 2>/dev/null

  echo "$out"
}
