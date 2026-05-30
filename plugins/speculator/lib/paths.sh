#!/usr/bin/env bash
# paths.sh — locate the project root, KB directory, and parse fields out of
# hook stdin JSON.
#
# Sourced by the speculator hooks. Defines functions only — no side effects,
# no `set` changes, safe to source from any shell.

# Project root from a given cwd: git toplevel if available, else the cwd.
#
# Usage: speculator_project_root [cwd]
speculator_project_root() {
  local cwd="${1:-$PWD}"
  ( cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null ) \
    || printf '%s\n' "$cwd"
}

# Knowledge base directory for a project: explicit $SPECULATOR_DIR override,
# else <project_root>/knowledge.
#
# Usage: speculator_kb_dir <project_root>
speculator_kb_dir() {
  local project_root="$1"
  printf '%s\n' "${SPECULATOR_DIR:-$project_root/knowledge}"
}

# Parse one top-level string field out of hook stdin JSON. Uses jq when
# available, otherwise a crude sed fallback. Prints empty on miss.
#
# Usage: speculator_field <json> <key>
speculator_field() {
  local input="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r ".${key} // empty" 2>/dev/null
  else
    printf '%s' "$input" \
      | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n1
  fi
}

# Convenience: parse cwd from hook stdin JSON, falling back to $PWD.
#
# Usage: speculator_cwd_from_stdin <json>
speculator_cwd_from_stdin() {
  local input="$1" cwd
  cwd="$(speculator_field "$input" cwd)"
  [ -n "$cwd" ] && printf '%s\n' "$cwd" || printf '%s\n' "$PWD"
}
