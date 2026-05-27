#!/usr/bin/env bash
# on_stop.sh — fires on Stop event (session ending).
#
# Marks PENDING_DEEP so the next session start (or next prompt) triggers
# a sub-agent crystallization pass for the just-finished session.

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/../lib/paths.sh" 2>/dev/null || exit 0

INPUT="$(cat 2>/dev/null || true)"
CWD="$(niblet_cwd_from_stdin "$INPUT")"
[ -z "$CWD" ] && CWD="$PWD"

PROJECT_ROOT="$(niblet_project_root "$CWD")"
STORE="$(niblet_store "$PROJECT_ROOT")"
mkdir -p "$STORE" 2>/dev/null || exit 0

touch "$STORE/PENDING_DEEP" 2>/dev/null
exit 0
