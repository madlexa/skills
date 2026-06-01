#!/usr/bin/env bash
# config.sh — load per-project niblet configuration from .niblet/config.
#
# The file is a simple KEY=VALUE sourceable bash file. It is loaded AFTER the
# script resolves PROJECT_ROOT so that project-level settings take precedence
# over anything inherited from the parent environment.

# niblet_load_config <project_root>
# Sources <project_root>/.niblet/config if it exists. Non-fatal on missing
# file or unreadable config. Returns 0 always.
niblet_load_config() {
  local project_root="${1:-}"
  [ -n "$project_root" ] || return 0
  local cfg="$project_root/.niblet/config"
  [ -f "$cfg" ] || return 0
  # Use a subshell to prevent a broken config from polluting the caller's
  # namespace on parse errors. Exported variables leak back via the parent
  # shell because we are not forking; a syntax error in the sourced file
  # would abort the whole process, so we validate it first with bash -n.
  if bash -n "$cfg" >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$cfg"
  fi
  return 0
}
