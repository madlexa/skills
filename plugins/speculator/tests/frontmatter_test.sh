#!/usr/bin/env bash
# frontmatter_test.sh — verify the skill and agent Markdown files have valid
# YAML frontmatter with the required keys.
#
# Checks, for SKILL.md and each agents/*.md:
#   1. File exists.
#   2. First line is a `---` frontmatter fence.
#   3. There is a closing `---` fence.
#   4. The frontmatter block contains non-empty `name:` and `description:` keys.
#
# Exit 0 = all checks pass; non-zero = a check failed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
SKILL="$PLUGIN_ROOT/skills/speculator/SKILL.md"
AGENTS_DIR="$PLUGIN_ROOT/agents"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# check_frontmatter <file>: validate fenced frontmatter with name + description.
check_frontmatter() {
  f="$1"
  [ -f "$f" ] || fail "$f not found"

  # First line must be exactly the opening fence.
  first="$(head -n 1 "$f")"
  [ "$first" = "---" ] || fail "$(basename "$f"): first line is not '---' frontmatter fence"

  # Extract the frontmatter block: lines between the 1st and 2nd '---'.
  fm="$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f")"
  [ -n "$fm" ] || fail "$(basename "$f"): empty or unterminated frontmatter block"

  # Require a closing fence to exist (a 2nd '---' line).
  fences="$(grep -c '^---[[:space:]]*$' "$f")"
  [ "$fences" -ge 2 ] || fail "$(basename "$f"): missing closing '---' fence"

  # name: must be present and non-empty.
  printf '%s\n' "$fm" | grep -Eq '^name:[[:space:]]*[^[:space:]].*$' \
    || fail "$(basename "$f"): missing or empty 'name:' in frontmatter"

  # description: must be present and non-empty.
  printf '%s\n' "$fm" | grep -Eq '^description:[[:space:]]*[^[:space:]].*$' \
    || fail "$(basename "$f"): missing or empty 'description:' in frontmatter"
}

check_frontmatter "$SKILL"

for a in "$AGENTS_DIR"/*.md; do
  [ -e "$a" ] || fail "no agent files found in $AGENTS_DIR"
  check_frontmatter "$a"
done

echo "OK: speculator skill + agents frontmatter"
