#!/usr/bin/env bash
# versioning_test.sh — contract tests for file-based versioning.
set -e

PROJECT_ROOT="/Users/Aleksey.Dobrynin/projects/madlexa/skills"
SCRIPT_DIR="$PROJECT_ROOT/plugins/niblet/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

mkdir -p "$TMP/.claude/skills/niblet/my-skill"
echo "v1" > "$TMP/.claude/skills/niblet/my-skill/SKILL.md"

# Save a version.
out=$("$SCRIPT_DIR/niblet-versioning" --project-root "$TMP" save --action UPDATE_SKILL --name my-skill)
[ -n "$out" ] || fail "save should output version path"
echo "$out" | grep -q "saved:" || fail "save output missing 'saved:'"

# List versions.
list_out=$("$SCRIPT_DIR/niblet-versioning" --project-root "$TMP" list --action UPDATE_SKILL --name my-skill)
[ -n "$list_out" ] || fail "list should output at least one version"
version_ts=$(basename "$list_out" .md)

# Update live file.
echo "v2" > "$TMP/.claude/skills/niblet/my-skill/SKILL.md"
[ "$(cat "$TMP/.claude/skills/niblet/my-skill/SKILL.md")" = "v2" ] || fail "live file not updated"

# Revert to saved version.
"$SCRIPT_DIR/niblet-revert" --project-root "$TMP" --action UPDATE_SKILL --name my-skill --ts "$version_ts" >/dev/null || fail "revert failed"
[ "$(cat "$TMP/.claude/skills/niblet/my-skill/SKILL.md")" = "v1" ] || fail "live file not reverted to v1"

# Revert of non-existent version should fail.
if "$SCRIPT_DIR/niblet-revert" --project-root "$TMP" --action UPDATE_SKILL --name my-skill --ts "19990101T000000Z" >/dev/null 2>&1; then
  fail "revert of missing version should fail"
fi

# niblet-promote must create a version on UPDATE_*.
mkdir -p "$TMP/.claude/skills/niblet/other-skill"
echo "original" > "$TMP/.claude/skills/niblet/other-skill/SKILL.md"
mkdir -p "$TMP/.niblet/proposals"
cat > "$TMP/.niblet/proposals/20260629T120000Z-UPDATE_SKILL-other-skill.md" <<'EOF'
---
action: UPDATE_SKILL
scope: project
target: /tmp/dummy/.claude/skills/niblet/other-skill/SKILL.md
name: other-skill
---
updated
EOF
# Fix target path to real tmp path.
sed -i.bak "s|/tmp/dummy|$TMP|" "$TMP/.niblet/proposals/20260629T120000Z-UPDATE_SKILL-other-skill.md"
rm "$TMP/.niblet/proposals/20260629T120000Z-UPDATE_SKILL-other-skill.md.bak"
( cd "$TMP" && "$SCRIPT_DIR/niblet-promote" "$TMP/.niblet/proposals/20260629T120000Z-UPDATE_SKILL-other-skill.md" >/dev/null )
[ -f "$TMP/.niblet/versions/skills/other-skill/"*.md ] || fail "niblet-promote did not create version"

echo "versioning tests passed"
