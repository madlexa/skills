#!/usr/bin/env bash
# pipelines_test.sh — contract tests for niblet pipelines.
set -e

PROJECT_ROOT="/Users/Aleksey.Dobrynin/projects/madlexa/skills"
SCRIPT="$PROJECT_ROOT/plugins/niblet/bin/niblet-pipelines"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

mkdir -p "$TMP/.niblet/pipelines"
cat > "$TMP/.niblet/pipelines/onboarding.md" <<'EOF'
---
name: onboarding
description: Set up a new project with niblet.
---
1. Initialize `.niblet/program.md`.
2. Run `niblet-status`.
EOF

# List should find the pipeline.
out=$("$SCRIPT" --project-root "$TMP" list)
printf '%s' "$out" | grep -q "onboarding" || fail "list should show onboarding"
printf '%s' "$out" | grep -q "Set up a new project" || fail "list should show description"

# Show should print the body.
show_out=$("$SCRIPT" --project-root "$TMP" show --name onboarding)
printf '%s' "$show_out" | grep -q "Initialize" || fail "show should print body"

# Run should record usage.
"$SCRIPT" --project-root "$TMP" run --name onboarding --session-id s1 --success true >/dev/null || fail "run failed"
[ -f "$TMP/.niblet/metrics/pipelines.jsonl" ] || fail "pipeline metrics not written"
grep -q '"pipeline"[[:space:]]*:[[:space:]]*"onboarding"' "$TMP/.niblet/metrics/pipelines.jsonl" || fail "onboarding metric missing"

# Unknown pipeline should fail.
if "$SCRIPT" --project-root "$TMP" show --name missing >/dev/null 2>&1; then
  fail "missing pipeline should fail"
fi

echo "pipeline tests passed"
