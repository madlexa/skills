#!/usr/bin/env bash
# smoke_test.sh — end-to-end smoke test for the speculator plugin.
#
# Consolidates the per-task checks from the migration plan (Tasks 1–8) into a
# single runnable suite. Each section either runs an inline check or delegates
# to the focused per-task test script that already lives in this directory, so
# logic is not duplicated.
#
#   1. plugin.json + package.json valid JSON, versions agree           (Task 1)
#   2. TypeScript type-checks with no errors (tsc --noEmit)            (Task 2)
#   3. bin/speculator wrapper runs `--help`                            (Task 3)
#   4. hook system (hooks.json + scripts) runs clean on empty env      (Task 4)
#   5. SKILL.md + agents have valid YAML frontmatter                   (Task 5)
#   6. lib/paths.sh + lib/graph.sh source and behave                   (Task 6)
#   7. root marketplace.json registers speculator                      (Task 8)
#   8. .mcp.json registers the speculator MCP server                   (Task 8)
#   9. index rebuild/binary-search comparator parity (locale-robust)   (review)
#  10. add_alias normalizes pipe/comma to a safe slug                   (review)
#
# Exit 0 = all checks pass; non-zero = at least one check failed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
PKG_JSON="$PLUGIN_ROOT/package.json"

FAIL=0
pass()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
title() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# run_subtest <label> <script>: run a focused per-task test, fold its result in.
run_subtest() {
  local label="$1" script="$2" out rc
  if [ ! -x "$script" ]; then
    fail "$label: $(basename "$script") missing or not executable"
    return
  fi
  out="$("$script" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$label"
  else
    fail "$label (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
}

# --- 1. plugin.json + package.json -------------------------------------------
title "1. plugin manifest + package.json"
if command -v jq >/dev/null 2>&1; then
  if jq -e . "$PLUGIN_JSON" >/dev/null 2>&1; then
    pass "plugin.json is valid JSON"
  else
    fail "plugin.json is not valid JSON"
  fi
  if jq -e . "$PKG_JSON" >/dev/null 2>&1; then
    pass "package.json is valid JSON"
  else
    fail "package.json is not valid JSON"
  fi
  jq -e '.name and .version and .description' "$PLUGIN_JSON" >/dev/null 2>&1 \
    && pass "plugin.json has name/version/description" \
    || fail "plugin.json missing name/version/description"
  pv="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)"
  kv="$(jq -r '.version // empty' "$PKG_JSON" 2>/dev/null)"
  if [ -n "$pv" ] && [ "$pv" = "$kv" ]; then
    pass "versions agree ($pv)"
  else
    fail "version mismatch: plugin.json=$pv package.json=$kv"
  fi
  for s in build typecheck test; do
    jq -e --arg s "$s" '.scripts[$s]' "$PKG_JSON" >/dev/null 2>&1 \
      && pass "package.json has '$s' script" \
      || fail "package.json missing '$s' script"
  done
else
  fail "jq not found; cannot validate JSON manifests"
fi

# --- 2. TypeScript type-check ------------------------------------------------
title "2. TypeScript type-check (tsc --noEmit)"
if [ -x "$PLUGIN_ROOT/node_modules/.bin/tsc" ] || command -v tsc >/dev/null 2>&1; then
  tsc_out="$(cd "$PLUGIN_ROOT" && npm run --silent typecheck 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "tsc --noEmit: no type errors"
  else
    fail "tsc --noEmit reported errors (exit $rc)"
    printf '%s\n' "$tsc_out" | sed 's/^/      /'
  fi
else
  printf '  \033[33m!\033[0m %s\n' "typescript not installed; skipping tsc (run 'npm install')"
fi

# --- 3. bin/speculator wrapper -----------------------------------------------
title "3. bin/speculator --help"
run_subtest "bin wrapper" "$SCRIPT_DIR/bin_test.sh"

# --- 4. hook system ----------------------------------------------------------
title "4. hooks (SessionStart + UserPromptSubmit)"
run_subtest "hooks" "$SCRIPT_DIR/hooks_test.sh"

# --- 5. skill + agents frontmatter -------------------------------------------
title "5. SKILL.md + agents frontmatter"
run_subtest "frontmatter" "$SCRIPT_DIR/frontmatter_test.sh"

# --- 6. bash libraries -------------------------------------------------------
title "6. lib (paths.sh + graph.sh)"
run_subtest "lib" "$SCRIPT_DIR/lib_test.sh"

# --- 7. marketplace registration ---------------------------------------------
title "7. marketplace registration"
run_subtest "marketplace" "$SCRIPT_DIR/marketplace_test.sh"

# --- 8. mcp.json registration ------------------------------------------------
title "8. .mcp.json registers the MCP server"
MCP_JSON="$PLUGIN_ROOT/.mcp.json"
if [ ! -f "$MCP_JSON" ]; then
  fail ".mcp.json not found (MCP server advertised in plugin.json is not wired)"
elif command -v jq >/dev/null 2>&1; then
  if jq -e . "$MCP_JSON" >/dev/null 2>&1; then
    pass ".mcp.json is valid JSON"
  else
    fail ".mcp.json is not valid JSON"
  fi
  jq -e '.mcpServers.speculator.command and (.mcpServers.speculator.args | length > 0)' \
    "$MCP_JSON" >/dev/null 2>&1 \
    && pass ".mcp.json registers the speculator server with a command + args" \
    || fail ".mcp.json missing mcpServers.speculator command/args"
  jq -e '.mcpServers.speculator.args | any(test("dist/mcp.js"))' \
    "$MCP_JSON" >/dev/null 2>&1 \
    && pass ".mcp.json points at dist/mcp.js" \
    || fail ".mcp.json does not reference dist/mcp.js"
else
  fail "jq not found; cannot validate .mcp.json"
fi

# --- 9. index comparator parity ----------------------------------------------
title "9. index rebuild/binary-search comparator parity"
run_subtest "index ordering" "$SCRIPT_DIR/index_order_test.sh"

# --- 10. alias normalization -------------------------------------------------
title "10. add_alias normalizes pipe/comma to a safe slug"
run_subtest "alias normalize" "$SCRIPT_DIR/alias_normalize_test.sh"

# --- summary -----------------------------------------------------------------
printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mAll smoke checks passed.\033[0m\n'
  exit 0
fi
printf '\033[31m%d smoke check(s) failed.\033[0m\n' "$FAIL"
exit 1
