#!/usr/bin/env bash
# metrics_test.sh — contract tests for niblet-metrics.
set -e

PROJECT_ROOT="/Users/Aleksey.Dobrynin/projects/madlexa/skills"
SCRIPT="$PROJECT_ROOT/plugins/niblet/bin/niblet-metrics"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

mkdir -p "$TMP/.niblet/metrics"
cat > "$TMP/.niblet/metrics/skills.jsonl" <<'EOF'
{"ts":"2026-06-29T10:00:00+00:00","session":"s1","skill":"good-skill","event":"used","success":true}
{"ts":"2026-06-29T11:00:00+00:00","session":"s2","skill":"good-skill","event":"used","success":true}
{"ts":"2026-06-29T12:00:00+00:00","session":"s3","skill":"good-skill","event":"used","success":true}
{"ts":"2026-06-29T12:00:00+00:00","session":"s3","skill":"bad-skill","event":"used","success":false}
{"ts":"2026-06-29T12:00:00+00:00","session":"s3","skill":"bad-skill","event":"used","success":false}
{"ts":"2026-06-29T12:00:00+00:00","session":"s3","skill":"bad-skill","event":"used","success":false}
EOF

out=$("$SCRIPT" --project-root "$TMP")
printf '%s' "$out" | grep -q "good-skill" || fail "good-skill missing"
printf '%s' "$out" | grep -q "bad-skill" || fail "bad-skill missing"
printf '%s' "$out" | grep -q "100%" || fail "good-skill should show 100%"
printf '%s' "$out" | grep -q "0%" || fail "bad-skill should show 0%"
printf '%s' "$out" | grep -q "Flagged for review" || fail "bad-skill should be flagged"

# JSON mode.
json_out=$("$SCRIPT" --project-root "$TMP" --json)
printf '%s' "$json_out" | grep -q '"name": "good-skill"' || fail "json missing good-skill"

# Empty project.
EMPTY=$(mktemp -d)
out_empty=$("$SCRIPT" --project-root "$EMPTY")
printf '%s' "$out_empty" | grep -q "No skills metrics" || fail "empty project message missing"

echo "metrics tests passed"
