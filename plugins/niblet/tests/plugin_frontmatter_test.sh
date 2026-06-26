#!/usr/bin/env bash
# plugin_frontmatter_test.sh — validate plugin-level skill + command frontmatter.
#
# These checks catch packaging mistakes that prevent the /niblet-distill
# slash command from appearing after plugin install.

set -e

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
title() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# Extract a YAML frontmatter value from a markdown file.
# Only handles simple "key: value" lines inside the first ---...--- block.
frontmatter_value() {
  local file="$1" key="$2"
  awk '
    BEGIN { inside=0 }
    /^---$/ { inside++; next }
    inside == 1 {
      if (match($0, "^" key ":[[:space:]]*")) {
        print substr($0, RSTART + RLENGTH)
        exit
      }
    }
  ' "key=$key" "$file"
}

# True if the file starts with a frontmatter block.
has_frontmatter() {
  head -n1 "$1" | grep -q '^---$'
}

title "1. skills/niblet/SKILL.md frontmatter"
SKILL_MAIN="$PLUGIN_DIR/skills/niblet/SKILL.md"
has_frontmatter "$SKILL_MAIN" && pass "has frontmatter block" || fail "missing frontmatter block"
[ "$(frontmatter_value "$SKILL_MAIN" name)" = "niblet" ] && pass "name: niblet" \
  || fail "name missing or wrong: $(frontmatter_value "$SKILL_MAIN" name)"
[ -n "$(frontmatter_value "$SKILL_MAIN" description)" ] && pass "description present" \
  || fail "description missing"
[ "$(frontmatter_value "$SKILL_MAIN" user-invocable)" = "false" ] && pass "user-invocable: false" \
  || fail "user-invocable should be false for the always-loaded skill"

title "2. skills/niblet-distill/SKILL.md frontmatter"
SKILL_DISTILL="$PLUGIN_DIR/skills/niblet-distill/SKILL.md"
[ -f "$SKILL_DISTILL" ] && pass "file exists" || fail "missing $SKILL_DISTILL"
has_frontmatter "$SKILL_DISTILL" && pass "has frontmatter block" || fail "missing frontmatter block"
[ "$(frontmatter_value "$SKILL_DISTILL" name)" = "niblet-distill" ] && pass "name: niblet-distill" \
  || fail "name missing or wrong: $(frontmatter_value "$SKILL_DISTILL" name)"
[ -n "$(frontmatter_value "$SKILL_DISTILL" description)" ] && pass "description present" \
  || fail "description missing"
[ "$(frontmatter_value "$SKILL_DISTILL" user-invocable)" = "true" ] && pass "user-invocable: true" \
  || fail "user-invocable must be true for /niblet-distill to appear in Kimi"

title "3. commands/niblet-distill.md frontmatter"
CMD_DISTILL="$PLUGIN_DIR/commands/niblet-distill.md"
[ -f "$CMD_DISTILL" ] && pass "file exists" || fail "missing $CMD_DISTILL"
has_frontmatter "$CMD_DISTILL" && pass "has frontmatter block" || fail "missing frontmatter block"
[ "$(frontmatter_value "$CMD_DISTILL" name)" = "niblet-distill" ] && pass "name: niblet-distill" \
  || fail "name missing or wrong: $(frontmatter_value "$CMD_DISTILL" name)"
[ -n "$(frontmatter_value "$CMD_DISTILL" description)" ] && pass "description present" \
  || fail "description missing"

title "4. kimi.plugin.json discovers all skills"
KIMI_MANIFEST="$PLUGIN_DIR/kimi.plugin.json"
[ -f "$KIMI_MANIFEST" ] && pass "manifest exists" || fail "missing $KIMI_MANIFEST"
if command -v jq >/dev/null 2>&1; then
  SKILLS_PATH="$(jq -r '.skills' "$KIMI_MANIFEST")"
  [ "$SKILLS_PATH" = "./skills/" ] && pass "skills path is ./skills/" \
    || fail "skills path is '$SKILLS_PATH' (expected ./skills/)"
else
  grep -q '"skills": "./skills/"' "$KIMI_MANIFEST" && pass "skills path is ./skills/" \
    || fail "skills path not ./skills/"
fi

title "5. niblet-distill agent prompt exists"
AGENT_DISTILL="$PLUGIN_DIR/agents/niblet-distill.md"
[ -f "$AGENT_DISTILL" ] && pass "agents/niblet-distill.md exists" || fail "missing $AGENT_DISTILL"

if [ "$FAIL" -eq 0 ]; then
  printf '\n\033[32mAll plugin frontmatter checks passed.\033[0m\n'
else
  printf '\n\033[31m%d check(s) failed.\033[0m\n' "$FAIL"
fi

exit "$FAIL"
