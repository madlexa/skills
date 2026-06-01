#!/usr/bin/env bash
# code_walker_test.sh — contract tests for niblet-code-walker wrapper.
set -e

PROJECT_ROOT="/Users/Aleksey.Dobrynin/projects/madlexa/skills"
SCRIPT="$PROJECT_ROOT/plugins/niblet/bin/niblet-code-walker"

fail() { echo "FAIL: $1"; exit 1; }

[ -x "$SCRIPT" ] || fail "script not executable"

out="$("$SCRIPT" "$PROJECT_ROOT")"
printf '%s' "$out" | grep -q "niblet-code-walker:" || fail "missing invocation label"
printf '%s' "$out" | grep -q "project_root=$PROJECT_ROOT" || fail "missing project_root"
printf '%s' "$out" | grep -q "niblet-code-walker.md" || fail "missing agent prompt path"

echo "code-walker tests passed"
