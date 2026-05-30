#!/usr/bin/env bash
# graph.sh — thin wrappers around the speculator CLI used by the hooks to
# read the knowledge graph (stats + search).
#
# Sourced by the speculator hooks. Defines functions only — no side effects.
# Every function is best-effort: it returns non-zero (and prints nothing) on
# any failure so callers can bail quietly without ever blocking a session.

# Locate the bundled CLI wrapper. Prints its path and returns 0 if it is an
# executable file, else returns 1.
#
# Usage: speculator_bin <plugin_root>
speculator_bin() {
  local plugin_root="$1"
  local bin="$plugin_root/bin/speculator"
  [ -x "$bin" ] || return 1
  printf '%s\n' "$bin"
}

# True (returns 0) if the KB directory exists and contains at least one
# markdown file. Returns 1 otherwise. Prints nothing.
#
# Usage: speculator_kb_has_md <kb_dir>
speculator_kb_has_md() {
  local kb_dir="$1" f
  [ -d "$kb_dir" ] || return 1
  for f in "$kb_dir"/*.md; do
    [ -f "$f" ] && return 0
  done
  return 1
}

# Preconditions shared by the read commands: node on PATH, a populated KB,
# and an executable CLI. Returns 0 and is otherwise silent when ready.
#
# Usage: speculator_graph_ready <plugin_root> <kb_dir>
speculator_graph_ready() {
  local plugin_root="$1" kb_dir="$2"
  command -v node >/dev/null 2>&1 || return 1
  speculator_kb_has_md "$kb_dir" || return 1
  speculator_bin "$plugin_root" >/dev/null || return 1
  return 0
}

# Print the `speculator stats` overview for a KB. Returns the CLI's exit code;
# prints nothing on failure.
#
# Usage: speculator_stats <plugin_root> <kb_dir>
speculator_stats() {
  local plugin_root="$1" kb_dir="$2" bin
  bin="$(speculator_bin "$plugin_root")" || return 1
  "$bin" --dir "$kb_dir" stats 2>/dev/null
}

# Run a graph search for the given query, surfacing slug + summary metadata.
# Terms are OR-matched (--any): an entity matches if it contains ANY of the
# query words, so a natural-language prompt reduced to keywords surfaces every
# related entity instead of requiring all words to co-occur in one entity.
# The query is passed as a single argv (never eval'd), so shell metacharacters
# in it are inert. Returns the CLI's exit code; prints nothing on failure.
#
# Usage: speculator_search <plugin_root> <kb_dir> <query>
speculator_search() {
  local plugin_root="$1" kb_dir="$2" query="$3" bin
  bin="$(speculator_bin "$plugin_root")" || return 1
  "$bin" --dir "$kb_dir" search "$query" --any --metadata slug,summary 2>/dev/null
}
