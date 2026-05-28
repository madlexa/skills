#!/usr/bin/env bash
# sanitize.sh — extract safe metadata + validate sub-agent-supplied names.
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

# niblet_validate_slug <candidate>
#
# Returns 0 if candidate is a safe single-segment filename / skill name:
#   - 1..64 chars
#   - starts with [a-z0-9]
#   - subsequent chars: [a-z0-9._-]
#   - no "/", "\", "..", or other path-tricks
# Returns non-zero otherwise. Prints nothing.
niblet_validate_slug() {
  local s="$1"
  [ -n "$s" ] || return 1
  # Length sanity
  [ "${#s}" -le 64 ] || return 1
  # Whole-string regex match (POSIX bash)
  case "$s" in
    .*|*..*) return 1 ;;
    */*|*\\*) return 1 ;;
  esac
  printf '%s' "$s" | LC_ALL=C grep -Eq '^[a-z0-9][a-z0-9._-]{0,63}$'
}

# niblet_canonical_path <path>
#
# Emit a lexically-canonical absolute path: relative → made absolute via $PWD,
# any "." segments dropped, any ".." segments collapsed. The path is NOT
# required to exist (so this works for proposed write targets). Tries python3
# first (handles all edge cases), falls back to a pure-bash collapse.
niblet_canonical_path() {
  local p="$1"
  [ -n "$p" ] || return 0

  if command -v python3 >/dev/null 2>&1; then
    # realpath() resolves symlinks where the path exists (handles macOS
    # /var → /private/var) and falls back to lexical normalization for
    # non-existent trailing segments. This is exactly what containment
    # checks need: both candidate and root land in the same realm.
    python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$p" 2>/dev/null && return 0
  fi

  # `realpath` is available on macOS (BSD) and most Linux distros (GNU
  # coreutils). Both resolve symlinks on existing prefixes; for tails that
  # don't exist yet, GNU realpath has `-m` and BSD silently fakes it.
  if command -v realpath >/dev/null 2>&1; then
    # Try GNU --canonicalize-missing first, then plain (BSD).
    realpath -m "$p"        2>/dev/null && return 0
    realpath    "$p"        2>/dev/null && return 0
  fi

  # Bash-only fallback: make absolute, then collapse . and ..
  # NOTE: this does NOT resolve symlinks. Callers concerned about
  # symlinks-in-path must additionally call niblet_assert_no_symlink_in_path.
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  local result=""
  local seg
  local oldIFS="$IFS"
  IFS=/
  # Disable globbing for the split iteration
  set -o noglob
  for seg in $p; do
    case "$seg" in
      ''|'.') ;;
      '..')   result="${result%/*}" ;;
      *)      result="$result/$seg" ;;
    esac
  done
  set +o noglob
  IFS="$oldIFS"
  [ -z "$result" ] && result="/"
  echo "$result"
}

# niblet_assert_under_dir <candidate_path> <allowed_root>
#
# Returns 0 iff the canonicalised candidate path is equal to or under the
# canonicalised allowed_root. Returns non-zero on any escape (../, symlink,
# absolute outside, etc.). Prints nothing on success; on failure prints
# "escape" to stderr.
niblet_assert_under_dir() {
  local candidate="$1"
  local root="$2"
  [ -n "$candidate" ] || return 1
  [ -n "$root" ]      || return 1

  local cc cr
  cc="$(niblet_canonical_path "$candidate")"
  cr="$(niblet_canonical_path "$root")"
  [ -n "$cc" ] || return 1
  [ -n "$cr" ] || return 1

  # Trailing slash to avoid /foo/barX matching /foo/bar
  case "$cc/" in
    "$cr/"*) return 0 ;;
  esac
  # Equal to root is also acceptable
  [ "$cc" = "$cr" ] && return 0
  echo "escape" >&2
  return 1
}

# niblet_assert_no_symlink_in_path <candidate_path> <allowed_root>
#
# Defence in depth on top of containment. Walks the existing prefix of
# candidate_path (its parent chain, plus the destination itself if it
# exists) and refuses if ANY segment between allowed_root (exclusive)
# and candidate (inclusive) is a symlink. This blocks attacks where a
# pre-existing symlink under the allowed dir points outside the realm —
# even when the canonicalizer is buggy or absent.
#
# Both arguments must already be canonicalised (caller's responsibility);
# this function only walks existing segments and tests `-L`.
niblet_assert_no_symlink_in_path() {
  local candidate="$1"
  local root="$2"
  [ -n "$candidate" ] || return 1
  [ -n "$root" ]      || return 1

  # Walk from candidate upward to root. Skip non-existent leaves; only
  # existing segments can be symlinks.
  local cur="$candidate"
  while [ -n "$cur" ] && [ "$cur" != "$root" ] && [ "$cur" != "/" ]; do
    if [ -L "$cur" ]; then
      echo "symlink-in-path:$cur" >&2
      return 1
    fi
    case "$cur" in
      "$root"/*) ;;
      *) break ;;  # walked above the allowed root
    esac
    cur="$(dirname "$cur")"
  done
  return 0
}
