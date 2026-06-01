#!/usr/bin/env bash
# paths.sh — detect runtime (Claude/Kimi), project root, artifact directories.
# Sourced by hooks. Defines functions, no side effects.

# Project root from a given cwd: git toplevel if available, else the cwd itself.
niblet_project_root() {
  local cwd="${1:-$PWD}"
  ( cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null ) \
    || echo "$cwd"
}

# Plugin storage inside a project (raw logs, markers, counters).
niblet_store() {
  local project_root="$1"
  echo "$project_root/.niblet"
}

# Detect which AI runtime invoked the hook or tool.
# Priority: explicit override → env vars → parent process name → presence of
# runtime config dirs → fallback.
niblet_runtime() {
  # 0. Explicit override (wrappers and tests can force a runtime).
  case "${NIBLET_RUNTIME:-}" in
    claude|kimi) echo "$NIBLET_RUNTIME"; return ;;
  esac

  # 1. Explicit env vars (highest confidence)
  if [ -n "${CLAUDE_CODE_SESSION:-}${CLAUDE_PROJECT_DIR:-}" ]; then
    echo "claude"; return
  fi
  if [ -n "${KIMI_SESSION:-}${KIMI_HOME:-}${KIMI_WORK_DIR:-}" ]; then
    echo "kimi"; return
  fi

  # 2. Parent process chain (useful when plugin tool is spawned by the runtime)
  if command -v ps >/dev/null 2>&1 && command -v sed >/dev/null 2>&1; then
    local parent_cmd
    parent_cmd="$(ps -o comm= -p "$PPID" 2>/dev/null | sed 's/^[[:space:]]*//')"
    case "$parent_cmd" in
      kimi|kimi-cli|python3*)
        # python3* because kimi-cli may run via python module
        echo "kimi"; return
        ;;
      claude|claude-cli|claude-code)
        echo "claude"; return
        ;;
    esac
  fi

  # 3. Config dir presence heuristic (when running from a shell inside the project)
  if [ -d "$PWD/.kimi" ] && [ ! -d "$PWD/.claude" ]; then
    echo "kimi"; return
  fi
  if [ -d "$PWD/.claude" ] && [ ! -d "$PWD/.kimi" ]; then
    echo "claude"; return
  fi

  # 4. Fallback
  echo "claude"
}

# Host home for the detected runtime.
niblet_runtime_home() {
  local rt="${1:-$(niblet_runtime)}"
  case "$rt" in
    kimi)   echo "${KIMI_HOME:-$HOME/.kimi}" ;;
    *)      echo "${CLAUDE_HOME:-$HOME/.claude}" ;;
  esac
}

# Path for an artifact category, given scope and project root.
#
# Usage: niblet_artifact_dir <kind> <scope> <project_root>
#   kind  ∈ {kb, skills, commands, agents, scripts, memory}
#   scope ∈ {project, global}
niblet_artifact_dir() {
  local kind="$1" scope="$2" project_root="$3"
  local rt; rt="$(niblet_runtime)"
  local rt_home; rt_home="$(niblet_runtime_home "$rt")"
  local base_subdir
  case "$rt" in
    kimi)  base_subdir=".kimi"   ;;
    *)     base_subdir=".claude" ;;
  esac

  if [ "$scope" = "global" ]; then
    case "$kind" in
      kb)        echo "$rt_home/kb" ;;
      skills)    echo "$rt_home/skills/niblet" ;;
      commands)  echo "$rt_home/commands/niblet" ;;
      agents)    echo "$rt_home/agents/niblet" ;;
      scripts)   echo "$rt_home/scripts/niblet" ;;
      memory)    echo "$rt_home/memory" ;;
      *)         echo "$rt_home/$kind" ;;
    esac
  else
    case "$kind" in
      kb)        echo "$project_root/$base_subdir/kb" ;;
      skills)    echo "$project_root/$base_subdir/skills/niblet" ;;
      commands)  echo "$project_root/$base_subdir/commands/niblet" ;;
      agents)    echo "$project_root/$base_subdir/agents/niblet" ;;
      scripts)   echo "$project_root/$base_subdir/scripts/niblet" ;;
      memory)    echo "$project_root/$base_subdir/memory" ;;
      *)         echo "$project_root/$base_subdir/$kind" ;;
    esac
  fi
}

# Parse cwd from hook stdin JSON. Falls back to $PWD if jq/parsing fails.
niblet_cwd_from_stdin() {
  local input="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$input" | jq -r '.cwd // empty' 2>/dev/null || echo "$PWD"
  else
    # crude fallback: grep for "cwd":"..."
    echo "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 \
      || echo "$PWD"
  fi
}
