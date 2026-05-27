#!/usr/bin/env bash
# on_session_start.sh — fires on SessionStart.
#
# Emits a compact KB index as a system reminder so the agent knows which
# project-specific findings are available for THIS session. Claude Code
# does NOT auto-load .claude/kb/ files; the user (or the agent) has to
# read them explicitly. This hook surfaces the table of contents.
#
# Index size is capped (~40 lines / 1500 chars) so it does not bloat the
# context window. Each entry shows: filename, H1 if present, and the first
# non-empty line below it (or the frontmatter description).

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/../lib/store.sh" 2>/dev/null || exit 0

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

CWD="$(field cwd)"; [ -z "$CWD" ] && CWD="$PWD"
PROJECT_ROOT="$(niblet_project_root "$CWD")"
KB_DIR="$(niblet_artifact_dir kb project "$PROJECT_ROOT")"

[ -d "$KB_DIR" ] || exit 0
# Anything to show?
count="$(find "$KB_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
[ "$count" -gt 0 ] || exit 0

# Build the index: per file, take H1 if available, else frontmatter description, else filename.
extract_blurb() {
  local file="$1"
  awk '
    BEGIN { in_fm=0; got=0 }
    NR == 1 && $0 == "---" { in_fm=1; next }
    in_fm && $0 == "---" { in_fm=0; next }
    in_fm && /^description:[[:space:]]*/ {
      v = $0; sub(/^description:[[:space:]]*/, "", v); fm = v
    }
    !in_fm && /^# / && !got { h1 = substr($0,3); got=1; next }
    !in_fm && got && /^[A-Za-z]/ && first == "" { first = $0; exit }
    END {
      if (h1 != "" && first != "") print h1 " — " first
      else if (h1 != "")           print h1
      else if (fm != "")           print fm
    }
  ' "$file" 2>/dev/null | head -c 120
}

printf 'NIBLET KB index for %s — %d topic(s) saved from previous sessions.\n' \
  "$PROJECT_ROOT" "$count"
printf 'Read the file directly when a topic looks relevant.\n\n'

MAX_LINES=40
n=0
for f in "$KB_DIR"/*.md; do
  [ -f "$f" ] || continue
  n=$((n + 1))
  [ "$n" -gt "$MAX_LINES" ] && { printf '  ... (%d more in %s/)\n' "$((count - n + 1))" "$KB_DIR"; break; }
  bn="$(basename "$f")"
  blurb="$(extract_blurb "$f")"
  if [ -n "$blurb" ]; then
    printf '  - %s — %s\n' "$bn" "$blurb"
  else
    printf '  - %s\n' "$bn"
  fi
done

exit 0
