#!/usr/bin/env bash
# ratchet_test.sh — contract tests for niblet-ratchet.
set -e

PROJECT_ROOT="/Users/Aleksey.Dobrynin/projects/madlexa/skills"
SCRIPT="$PROJECT_ROOT/plugins/niblet/bin/niblet-ratchet"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

mkdir -p "$TMP/.niblet/proposals" "$TMP/.claude/skills/niblet/bad-skill"
echo "v1" > "$TMP/.claude/skills/niblet/bad-skill/SKILL.md"
mkdir -p "$TMP/.niblet/metrics"
cat > "$TMP/.niblet/metrics/skills.jsonl" <<'EOF'
{"ts":"2026-06-29T10:00:00+00:00","session":"s1","skill":"bad-skill","event":"used","success":false}
{"ts":"2026-06-29T11:00:00+00:00","session":"s2","skill":"bad-skill","event":"used","success":false}
{"ts":"2026-06-29T12:00:00+00:00","session":"s3","skill":"bad-skill","event":"used","success":false}
EOF

cat > "$TMP/.niblet/proposals/20260629T120000Z-UPDATE_SKILL-bad-skill.md" <<'EOF'
---
action: UPDATE_SKILL
scope: project
name: bad-skill
risk: low
confidence: high
---
updated skill body
EOF

# Dry-run should recommend promotion but not change files.
out=$("$SCRIPT" --project-root "$TMP" --dry-run)
printf '%s' "$out" | grep -q "promote" || fail "dry-run should recommend promote"
[ "$(cat "$TMP/.claude/skills/niblet/bad-skill/SKILL.md")" = "v1" ] || fail "dry-run should not modify live file"

# Real run should promote.
"$SCRIPT" --project-root "$TMP" >/dev/null || fail "ratchet run failed"
[ "$(cat "$TMP/.claude/skills/niblet/bad-skill/SKILL.md")" = "updated skill body" ] || fail "ratchet did not promote"
[ -f "$TMP/.niblet/versions/skills/bad-skill/"*.md ] || fail "ratchet did not save version"

# CREATE_* proposals should stay in review.
mkdir -p "$TMP/.claude/skills/niblet/new-skill"
cat > "$TMP/.niblet/proposals/20260629T120000Z-CREATE_SKILL-new-skill.md" <<'EOF'
---
action: CREATE_SKILL
scope: project
name: new-skill
risk: low
confidence: high
---
new skill body
EOF
out2=$("$SCRIPT" --project-root "$TMP" --dry-run)
printf '%s' "$out2" | grep -q "review" || fail "CREATE_SKILL should be marked for review"

echo "ratchet tests passed"
