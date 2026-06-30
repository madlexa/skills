#!/usr/bin/env bash
# program_test.sh — contract tests for niblet-program.
set -e

PROJECT_ROOT="/Users/Aleksey.Dobrynin/projects/madlexa/skills"
SCRIPT="$PROJECT_ROOT/plugins/niblet/bin/niblet-program"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

# Existing program validates.
"$SCRIPT" --project-root "$PROJECT_ROOT" --validate >/dev/null || fail "existing program should validate"

# Key extraction works.
out=$("$SCRIPT" --project-root "$PROJECT_ROOT" --key mission)
[ -n "$out" ] || fail "mission should be non-empty"

# Missing program is reported.
mkdir -p "$TMP/.niblet"
if "$SCRIPT" --project-root "$TMP" --validate >/dev/null 2>&1; then
  fail "missing program should fail validation"
fi

# Invalid program (missing required sections) is rejected.
cat > "$TMP/.niblet/program.md" <<'EOF'
# Niblet program

## Mission
Only mission here.
EOF
if "$SCRIPT" --project-root "$TMP" --validate >/dev/null 2>&1; then
  fail "program missing required sections should fail validation"
fi

# Valid minimal program passes.
cat > "$TMP/.niblet/program.md" <<'EOF'
# Niblet program

## Mission
Capture patterns.

## Knowledge taxonomy
- component-overview

## Auto-write policy
- KB entries auto-write.
EOF
"$SCRIPT" --project-root "$TMP" --validate >/dev/null || fail "valid minimal program should validate"

echo "program tests passed"
