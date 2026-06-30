#!/usr/bin/env bash
# maintain_test.sh — contract tests for niblet-maintain.
set -e

PROJECT_ROOT="/Users/Aleksey.Dobrynin/projects/madlexa/skills"
SCRIPT="$PROJECT_ROOT/plugins/niblet/bin/niblet-maintain"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

# Dry-run should succeed and report queues.
out=$("$SCRIPT" --project-root "$TMP" --dry-run)
printf '%s' "$out" | grep -q "ratchet" || fail "ratchet section missing"
printf '%s' "$out" | grep -q "gardener" || fail "gardener section missing"
printf '%s' "$out" | grep -q "agent-required queues" || fail "queue section missing"
printf '%s' "$out" | grep -q "deep: 0" || fail "deep count missing"
printf '%s' "$out" | grep -q "code-walker: 0" || fail "code-walker count missing"

echo "maintain tests passed"
