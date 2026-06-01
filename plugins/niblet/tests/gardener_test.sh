#!/usr/bin/env bash
# gardener_test.sh — contract tests for gardener helpers.
set -e

PROJECT_ROOT="/Users/Aleksey.Dobrynin/projects/madlexa/skills"
. "$PROJECT_ROOT/plugins/niblet/lib/gardener.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

# --- niblet_proposal_key ---
cat > "$TMP/sample.md" <<'EOF'
---
action: CREATE_SKILL
scope: project
risk: low
confidence: high
name: sample
---
body
EOF

[ "$(niblet_proposal_key "$TMP/sample.md" action)" = "CREATE_SKILL" ] || fail "action extraction"
[ "$(niblet_proposal_key "$TMP/sample.md" scope)" = "project" ] || fail "scope extraction"
[ "$(niblet_proposal_key "$TMP/sample.md" missing)" = "" ] || fail "missing key returns empty"

# --- eligible project CREATE_SKILL ---
cp "$TMP/sample.md" "$TMP/eligible.md"
niblet_proposal_can_autopromote "$TMP/eligible.md" || fail "eligible project CREATE_SKILL"

# --- global scope rejected ---
sed 's/scope: project/scope: global/' "$TMP/sample.md" > "$TMP/global.md"
if niblet_proposal_can_autopromote "$TMP/global.md"; then fail "global should not autopromote"; fi

# --- medium confidence rejected ---
sed 's/confidence: high/confidence: medium/' "$TMP/sample.md" > "$TMP/medium.md"
if niblet_proposal_can_autopromote "$TMP/medium.md"; then fail "medium confidence should not autopromote"; fi

# --- high risk rejected ---
sed 's/risk: low/risk: high/' "$TMP/sample.md" > "$TMP/highrisk.md"
if niblet_proposal_can_autopromote "$TMP/highrisk.md"; then fail "high risk should not autopromote"; fi

# --- rejected_reason rejected ---
cat > "$TMP/rejected.md" <<'EOF'
---
action: CREATE_SKILL
scope: project
risk: low
confidence: high
rejected_reason: bad slug
---
body
EOF
if niblet_proposal_can_autopromote "$TMP/rejected.md"; then fail "rejected proposal should not autopromote"; fi

# --- skip reason ---
[ "$(niblet_proposal_skip_reason "$TMP/eligible.md")" = "eligible" ] || fail "eligible skip reason"
[ "$(niblet_proposal_skip_reason "$TMP/global.md")" = "global-scope" ] || fail "global skip reason"
[ "$(niblet_proposal_skip_reason "$TMP/medium.md")" = "confidence=medium" ] || fail "medium skip reason"
[ "$(niblet_proposal_skip_reason "$TMP/highrisk.md")" = "risk=high" ] || fail "high risk skip reason"
[ "$(niblet_proposal_skip_reason "$TMP/rejected.md")" = "rejected" ] || fail "rejected skip reason"

echo "gardener tests passed"
