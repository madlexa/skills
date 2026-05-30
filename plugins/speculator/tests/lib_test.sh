#!/usr/bin/env bash
# lib_test.sh — verify the speculator bash libraries (lib/paths.sh, lib/graph.sh).
#
# Checks:
#   1. Both libs exist and source cleanly (no errors, no side effects).
#   2. speculator_project_root returns the git toplevel for a repo cwd and
#      falls back to the cwd itself for a non-repo directory.
#   3. speculator_kb_dir honours $SPECULATOR_DIR and otherwise derives
#      <project_root>/knowledge.
#   4. speculator_field parses a key out of hook stdin JSON.
#   5. speculator_kb_has_md / speculator_bin behave on empty + populated dirs.
#
# Exit 0 = all checks pass; non-zero = a check failed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
PATHS_LIB="$PLUGIN_ROOT/lib/paths.sh"
GRAPH_LIB="$PLUGIN_ROOT/lib/graph.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[ -f "$PATHS_LIB" ] || fail "lib/paths.sh not found"
[ -f "$GRAPH_LIB" ] || fail "lib/graph.sh not found"

# --- source both libs; must not error or emit output ---
src_out="$(. "$PATHS_LIB" && . "$GRAPH_LIB" 2>&1)"
rc=$?
[ "$rc" -eq 0 ] || fail "sourcing libs exited $rc"
[ -z "$src_out" ] || fail "sourcing libs produced output: $src_out"

# shellcheck source=../lib/paths.sh
. "$PATHS_LIB"
# shellcheck source=../lib/graph.sh
. "$GRAPH_LIB"

# --- speculator_project_root: git toplevel inside this repo ---
expected_root="$(cd "$PLUGIN_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"
got_root="$(speculator_project_root "$PLUGIN_ROOT")"
if [ -n "$expected_root" ]; then
  [ "$got_root" = "$expected_root" ] \
    || fail "project_root: expected '$expected_root', got '$got_root'"
fi

# --- speculator_project_root: non-repo dir falls back to the dir itself ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
got_tmp_root="$(speculator_project_root "$TMP")"
# On macOS mktemp may live under /var -> /private/var symlink; compare resolved.
resolved_tmp="$(cd "$TMP" && pwd -P)"
resolved_got="$(cd "$got_tmp_root" 2>/dev/null && pwd -P)"
[ "$resolved_got" = "$resolved_tmp" ] \
  || fail "project_root fallback: expected '$resolved_tmp', got '$resolved_got'"

# --- speculator_kb_dir: default and override ---
unset SPECULATOR_DIR
[ "$(speculator_kb_dir /proj)" = "/proj/knowledge" ] \
  || fail "kb_dir default wrong: $(speculator_kb_dir /proj)"
( export SPECULATOR_DIR="/custom/kb"
  [ "$(speculator_kb_dir /proj)" = "/custom/kb" ] \
    || { printf 'FAIL: kb_dir override wrong\n' >&2; exit 1; }
) || exit 1

# --- speculator_field: parse a key from JSON ---
js='{"cwd":"/a/b","prompt":"hello"}'
[ "$(speculator_field "$js" cwd)" = "/a/b" ] || fail "field cwd parse wrong"
[ "$(speculator_field "$js" prompt)" = "hello" ] || fail "field prompt parse wrong"
[ -z "$(speculator_field "$js" missing)" ] || fail "field missing should be empty"

# --- speculator_cwd_from_stdin: present and fallback ---
[ "$(speculator_cwd_from_stdin "$js")" = "/a/b" ] || fail "cwd_from_stdin wrong"
[ -n "$(speculator_cwd_from_stdin '{}')" ] || fail "cwd_from_stdin should fall back to PWD"

# --- speculator_kb_has_md: empty vs populated ---
speculator_kb_has_md "$TMP" && fail "kb_has_md should be false on empty dir"
touch "$TMP/entity.md"
speculator_kb_has_md "$TMP" || fail "kb_has_md should be true with a .md file"

# --- speculator_bin: resolves the wrapper if present ---
if [ -x "$PLUGIN_ROOT/bin/speculator" ]; then
  [ "$(speculator_bin "$PLUGIN_ROOT")" = "$PLUGIN_ROOT/bin/speculator" ] \
    || fail "speculator_bin did not resolve the wrapper"
fi
speculator_bin "$TMP" >/dev/null 2>&1 \
  && fail "speculator_bin should fail when no bin/speculator exists"

echo "OK: speculator lib (paths.sh, graph.sh)"
