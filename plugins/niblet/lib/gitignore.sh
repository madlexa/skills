#!/usr/bin/env bash
# gitignore.sh — idempotent .gitignore management.

# Add an entry to <project_root>/.gitignore if not already present.
# Creates .gitignore if missing. Always succeeds; never aborts the caller.
gitignore_add() {
  local project_root="$1"
  local entry="$2"
  local gitignore="$project_root/.gitignore"

  [ -n "$project_root" ] || return 0
  [ -n "$entry" ]        || return 0
  [ -d "$project_root" ] || return 0

  if [ -f "$gitignore" ]; then
    if grep -qxF "$entry" "$gitignore" 2>/dev/null; then
      return 0
    fi
    # Ensure trailing newline before appending
    if [ -s "$gitignore" ] && [ "$(tail -c1 "$gitignore" 2>/dev/null)" != "" ]; then
      printf '\n' >> "$gitignore"
    fi
  fi
  printf '%s\n' "$entry" >> "$gitignore" 2>/dev/null || true
}
