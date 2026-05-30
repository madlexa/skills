#!/usr/bin/env bash
# hooks_test.sh — verify the speculator hook system.
#
# Checks:
#   1. hooks.json exists and is valid JSON (jq) registering SessionStart
#      and UserPromptSubmit -> the matching hook scripts.
#   2. on_session_start.sh and on_prompt_submit.sh exist and are executable.
#   3. Each hook runs and exits 0 on an EMPTY environment (no KB, empty
#      stdin) — hooks must never block a session.
#   4. Each hook stays quiet (exits 0, no crash) when given a prompt but no
#      knowledge base directory.
#
# Exit 0 = all checks pass; non-zero = a check failed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
HOOKS_DIR="$PLUGIN_ROOT/hooks"
HOOKS_JSON="$HOOKS_DIR/hooks.json"
START="$HOOKS_DIR/on_session_start.sh"
SUBMIT="$HOOKS_DIR/on_prompt_submit.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# --- hooks.json ---
[ -f "$HOOKS_JSON" ] || fail "hooks.json not found"
if command -v jq >/dev/null 2>&1; then
  jq -e . "$HOOKS_JSON" >/dev/null 2>&1 || fail "hooks.json is not valid JSON"
  jq -e '.hooks.SessionStart' "$HOOKS_JSON" >/dev/null 2>&1 \
    || fail "hooks.json missing SessionStart"
  jq -e '.hooks.UserPromptSubmit' "$HOOKS_JSON" >/dev/null 2>&1 \
    || fail "hooks.json missing UserPromptSubmit"
  grep -q 'on_session_start.sh' "$HOOKS_JSON" \
    || fail "hooks.json does not reference on_session_start.sh"
  grep -q 'on_prompt_submit.sh' "$HOOKS_JSON" \
    || fail "hooks.json does not reference on_prompt_submit.sh"
else
  printf 'WARN: jq not found; skipping hooks.json schema checks\n' >&2
fi

# --- scripts exist and are executable ---
for s in "$START" "$SUBMIT"; do
  [ -f "$s" ] || fail "$(basename "$s") not found"
  [ -x "$s" ] || fail "$(basename "$s") is not executable"
done

# --- run on an empty environment in an isolated temp dir (no KB) ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
( cd "$TMP" || exit 1
  # Force KB lookup at a path that does not exist.
  export SPECULATOR_DIR="$TMP/nope-knowledge"

  printf '{}' | "$START" >/dev/null 2>&1
  rc=$?; [ "$rc" -eq 0 ] || { printf 'FAIL: on_session_start.sh exited %s on empty env\n' "$rc" >&2; exit 1; }

  printf '{}' | "$SUBMIT" >/dev/null 2>&1
  rc=$?; [ "$rc" -eq 0 ] || { printf 'FAIL: on_prompt_submit.sh exited %s on empty env\n' "$rc" >&2; exit 1; }

  # With a prompt but still no KB: must stay quiet and exit 0.
  printf '{"cwd":"%s","prompt":"hello world"}' "$TMP" | "$SUBMIT" >/dev/null 2>&1
  rc=$?; [ "$rc" -eq 0 ] || { printf 'FAIL: on_prompt_submit.sh exited %s with prompt/no-KB\n' "$rc" >&2; exit 1; }
) || exit 1

# --- populated KB: a realistic multi-word prompt surfaces matches ---
# Regression guard: the prompt hook must OR-match salient keywords, not require
# every word (incl. stopwords) to co-occur in one entity. Passing the raw
# sentence to an AND search matched nothing for natural prompts.
if command -v node >/dev/null 2>&1; then
  BIN="$PLUGIN_ROOT/bin/speculator"
  [ -x "$BIN" ] || fail "bin/speculator not executable"
  KB2="$TMP/kb-populated"
  "$BIN" init "$KB2" >/dev/null 2>&1 || fail "could not init test KB"
  out="$(printf '{"cwd":"%s","prompt":"can you explain how the example entity is wired"}' "$TMP" \
        | SPECULATOR_DIR="$KB2" "$SUBMIT" 2>/dev/null)"
  printf '%s' "$out" | grep -q "example" \
    || fail "on_prompt_submit.sh emitted no match for a multi-word prompt naming a KB entity"
else
  printf 'WARN: node not found; skipping populated-KB prompt match check\n' >&2
fi

echo "OK: speculator hooks"
