#!/usr/bin/env bash
# store.sh — single entry point that initializes a project's .niblet/ store.
#
# Idempotent: safe to call from every hook on every invocation. Creates the
# store directory tree and writes a .gitignore inside .niblet/ so the store
# stays untracked without modifying the project root .gitignore. Optionally
# creates per-session subdirectory.
#
# Sources lib/paths.sh — the caller does NOT need to source it separately.

# Resolve sibling lib scripts.
__niblet_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$__niblet_lib_dir/paths.sh" 2>/dev/null
unset __niblet_lib_dir

# niblet_ensure_store <project_root> [<session_id>]
#
# Creates <project_root>/.niblet/ subdirectory tree. Writes .niblet/.gitignore
# (content: *) so the store stays untracked without touching the project root
# .gitignore. When a session_id is supplied, also creates the per-session
# subdirectory.
#
# Echoes the store path to stdout (so callers can capture it). Never fails.
niblet_ensure_store() {
  local project_root="$1"
  local session_id="${2:-}"
  [ -n "$project_root" ] || return 0

  local store; store="$(niblet_store "$project_root")"
  mkdir -p "$store/raw" "$store/log" "$store/sessions" "$store/inbox" \
           "$store/digests" "$store/index" "$store/distill_queue" "$store/audit_queue" 2>/dev/null

  # Write .gitignore inside the store to keep everything untracked.
  local gi="$store/.gitignore"
  [ -f "$gi" ] || printf '*\n' > "$gi" 2>/dev/null || true

  if [ -n "$session_id" ]; then
    mkdir -p "$store/sessions/$session_id" 2>/dev/null
  fi

  echo "$store"
}

# niblet_session_dir <project_root> <session_id>
#
# Returns the per-session subdirectory path. Does NOT create it — call
# niblet_ensure_store with both args to materialize it.
niblet_session_dir() {
  local project_root="$1"
  local session_id="$2"
  [ -n "$project_root" ] || return 0
  [ -n "$session_id" ]   || return 0
  echo "$(niblet_store "$project_root")/sessions/$session_id"
}
