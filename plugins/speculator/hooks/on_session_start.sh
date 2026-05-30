#!/usr/bin/env bash
# on_session_start.sh — fires on SessionStart.
#
# Surfaces a compact summary of the speculator knowledge base (entity/edge
# counts and the most-connected entities) so the agent knows a graph KB is
# available for THIS project before it does any work. Claude Code does not
# auto-load the KB; this hook just emits the `speculator stats` overview as
# a system reminder.
#
# The hook is best-effort and MUST NOT block the session: every failure
# path (no node, no KB, CLI error, empty KB) exits 0 quietly.

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"

# shellcheck source=../lib/paths.sh
. "$PLUGIN_ROOT/lib/paths.sh" 2>/dev/null || exit 0
# shellcheck source=../lib/graph.sh
. "$PLUGIN_ROOT/lib/graph.sh" 2>/dev/null || exit 0

INPUT="$(cat 2>/dev/null || true)"

CWD="$(speculator_cwd_from_stdin "$INPUT")"
PROJECT_ROOT="$(speculator_project_root "$CWD")"
KB_DIR="$(speculator_kb_dir "$PROJECT_ROOT")"

# Bail quietly unless node, a populated KB, and the CLI are all present.
speculator_graph_ready "$PLUGIN_ROOT" "$KB_DIR" || exit 0

STATS="$(speculator_stats "$PLUGIN_ROOT" "$KB_DIR")"
rc=$?
[ "$rc" -eq 0 ] || exit 0
[ -n "$STATS" ] || exit 0

# Cap the surfaced output so it does not bloat the context window.
printf 'SPECULATOR knowledge base for %s — graph KB available this session.\n' "$KB_DIR"
printf 'Query it with `speculator search <terms>` or read entities under %s.\n\n' "$KB_DIR"
printf '%s\n' "$STATS" | head -n 40

exit 0
