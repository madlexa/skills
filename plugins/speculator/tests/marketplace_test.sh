#!/usr/bin/env bash
# marketplace_test.sh — verify the root marketplace.json registers speculator.
#
# Checks (Task 8):
#   1. root .claude-plugin/marketplace.json is valid JSON
#   2. it contains a plugins[] entry named "speculator"
#   3. that entry's source path resolves to this plugin directory
#   4. the entry's version matches the plugin's own plugin.json version
#
# Exit 0 = all checks pass; non-zero = at least one check failed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." 2>/dev/null && pwd)"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

FAIL=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }

if ! command -v jq >/dev/null 2>&1; then
  fail "jq not found; cannot validate marketplace.json"
  exit 1
fi

if [ ! -f "$MARKETPLACE" ]; then
  fail "marketplace.json not found at $MARKETPLACE"
  exit 1
fi

if jq -e . "$MARKETPLACE" >/dev/null 2>&1; then
  pass "marketplace.json is valid JSON"
else
  fail "marketplace.json is not valid JSON"
  exit 1
fi

# 2. has a speculator entry
entry="$(jq -c '.plugins[] | select(.name == "speculator")' "$MARKETPLACE" 2>/dev/null)"
if [ -n "$entry" ]; then
  pass "marketplace.json contains a 'speculator' entry"
else
  fail "marketplace.json has no 'speculator' entry"
  exit 1
fi

# entry has name/source/description/version
for field in name source description version; do
  printf '%s' "$entry" | jq -e --arg f "$field" '.[$f] // empty' >/dev/null 2>&1 \
    && pass "speculator entry has '$field'" \
    || fail "speculator entry missing '$field'"
done

# 3. source resolves to this plugin directory
src="$(printf '%s' "$entry" | jq -r '.source // empty')"
resolved="$(cd "$REPO_ROOT" && cd "$src" 2>/dev/null && pwd)"
if [ -n "$resolved" ] && [ "$resolved" = "$PLUGIN_ROOT" ]; then
  pass "source '$src' resolves to plugin dir"
else
  fail "source '$src' does not resolve to $PLUGIN_ROOT (got '${resolved:-unresolved}')"
fi

# 4. version agreement with plugin.json
mv="$(printf '%s' "$entry" | jq -r '.version // empty')"
pv="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)"
if [ -n "$mv" ] && [ "$mv" = "$pv" ]; then
  pass "version agrees with plugin.json ($mv)"
else
  fail "version mismatch: marketplace=$mv plugin.json=$pv"
fi

if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mmarketplace_test: all checks passed.\033[0m\n'
  exit 0
fi
printf '\033[31mmarketplace_test: %d check(s) failed.\033[0m\n' "$FAIL"
exit 1
