#!/usr/bin/env bash
# sanitize.sh — extract safe metadata from Claude Code hook input.
#
# Workflow patterns are sequences of (tool, path, success). The PLUGIN MUST
# NOT store raw tool_input or tool_response content — those can include
# secrets, file contents, env vars, and untrusted text that becomes
# persistent prompt injection when read back by a sub-agent.
#
# Every function here returns a sanitized scalar. They never echo raw JSON
# blobs or shell-evaluated input.

# niblet_safe_path <tool_name> <tool_input_json>
#
# For Read/Edit/Write/MultiEdit/NotebookEdit: returns the file_path (or
# notebook_path) field, project-relative when possible.
# For Bash: returns the empty string (we deliberately do NOT log command args).
# For Glob/Grep: returns the search root path if present, else "".
# Anything else: "".
niblet_safe_path() {
  local tool="$1"
  local input="$2"
  [ -n "$tool" ]  || return 0
  [ -n "$input" ] || return 0

  command -v jq >/dev/null 2>&1 || { echo ""; return 0; }

  case "$tool" in
    Read|Edit|MultiEdit|Write)
      printf '%s' "$input" | jq -r '.file_path // ""' 2>/dev/null
      ;;
    NotebookEdit)
      printf '%s' "$input" | jq -r '.notebook_path // ""' 2>/dev/null
      ;;
    Glob|Grep)
      printf '%s' "$input" | jq -r '.path // ""' 2>/dev/null
      ;;
    *)
      echo ""
      ;;
  esac
}

# niblet_safe_exit_code <tool_response_json>
#
# Returns the exit code if the tool reports one (Bash). Otherwise "".
# Never returns stdout/stderr content.
niblet_safe_exit_code() {
  local response="$1"
  [ -n "$response" ] || return 0
  command -v jq >/dev/null 2>&1 || { echo ""; return 0; }
  printf '%s' "$response" | jq -r '.exit_code // empty' 2>/dev/null
}

# niblet_safe_success <tool_response_json>
#
# Returns "true" or "false" based on whether the tool reported an error.
# Never returns the error text itself.
niblet_safe_success() {
  local response="$1"
  [ -n "$response" ] || { echo "true"; return 0; }
  command -v jq >/dev/null 2>&1 || { echo "true"; return 0; }

  # If "is_error" is true OR exit_code != 0 → false; otherwise true
  local is_error exit_code
  is_error="$(printf '%s' "$response"  | jq -r '.is_error // false' 2>/dev/null)"
  exit_code="$(printf '%s' "$response" | jq -r '.exit_code // 0'    2>/dev/null)"
  if [ "$is_error" = "true" ] || [ "$exit_code" != "0" -a "$exit_code" != "" ]; then
    echo "false"
  else
    echo "true"
  fi
}

# niblet_project_relative_path <project_root> <abs_path>
#
# If abs_path is under project_root, return the relative form. Handles
# macOS /private/var ↔ /var symlink mismatch by also matching against the
# canonical (pwd -P) form of project_root. Never returns content; just
# rewrites the path.
niblet_project_relative_path() {
  local project_root="$1"
  local path="$2"
  [ -n "$path" ] || { echo ""; return 0; }
  [ -n "$project_root" ] || { echo "$path"; return 0; }

  case "$path" in
    "$project_root"/*)
      echo "${path#"$project_root"/}"
      return 0
      ;;
  esac

  # Try canonical form of project_root (resolves /tmp ↔ /private/tmp)
  local canonical
  canonical="$(cd "$project_root" 2>/dev/null && pwd -P)"
  if [ -n "$canonical" ] && [ "$canonical" != "$project_root" ]; then
    case "$path" in
      "$canonical"/*)
        echo "${path#"$canonical"/}"
        return 0
        ;;
    esac
  fi

  # macOS quirk: /private/var ↔ /var. Strip from either side.
  case "$path" in
    /private/*)
      local stripped_path="${path#/private}"
      case "$stripped_path" in
        "$project_root"/*)
          echo "${stripped_path#"$project_root"/}"
          return 0
          ;;
      esac
      ;;
  esac
  case "$project_root" in
    /private/*)
      local stripped_root="${project_root#/private}"
      case "$path" in
        "$stripped_root"/*)
          echo "${path#"$stripped_root"/}"
          return 0
          ;;
      esac
      ;;
  esac

  echo "$path"
}
