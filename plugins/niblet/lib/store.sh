#!/usr/bin/env bash
# store.sh — single entry point that initializes a project's .niblet/ store.
#
# Idempotent: safe to call from every hook on every invocation. Creates the
# store directory tree and ensures .niblet/ is gitignored when the project
# is a git repository. Optionally creates per-session subdirectory.
#
# Sources lib/paths.sh and lib/gitignore.sh — the caller does NOT need to
# source them separately if it sources this file.

# Resolve sibling lib scripts.
__niblet_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$__niblet_lib_dir/paths.sh"     2>/dev/null
. "$__niblet_lib_dir/gitignore.sh" 2>/dev/null
unset __niblet_lib_dir

# niblet_ensure_store <project_root> [<session_id>]
#
# Creates <project_root>/.niblet/{raw,log,sessions} on first call. Adds
# .niblet/ to .gitignore exactly once if the project is under git. When a
# session_id is supplied, also creates the per-session subdirectory.
#
# Echoes the store path to stdout (so callers can capture it). Never fails.
niblet_ensure_store() {
  local project_root="$1"
  local session_id="${2:-}"
  [ -n "$project_root" ] || return 0

  local store; store="$(niblet_store "$project_root")"
  mkdir -p "$store/raw" "$store/log" "$store/sessions" 2>/dev/null

  # Register .niblet/ with .gitignore only if this looks like a git repo.
  if [ -d "$project_root/.git" ] || \
     ( cd "$project_root" 2>/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1 ); then
    gitignore_add "$project_root" ".niblet/"
  fi

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
