#!/usr/bin/env bash
# jsonl.sh — append helpers for JSONL files.

# Atomically append one JSON line to a file.
# Usage: jsonl_append <file> <json_string>
jsonl_append() {
  local file="$1"
  local line="$2"
  [ -n "$file" ] || return 0
  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  # Strip any embedded newlines from the JSON line before append
  printf '%s\n' "${line//$'\n'/ }" >> "$file" 2>/dev/null || true
}

# JSON-escape a string value (no surrounding quotes).
# Handles backslashes, double quotes, control chars roughly.
jsonl_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Truncate a string to N chars (default 500) and JSON-escape.
jsonl_truncate_escape() {
  local s="$1"
  local n="${2:-500}"
  if [ "${#s}" -gt "$n" ]; then
    s="${s:0:$n}..."
  fi
  jsonl_escape "$s"
}

# Build a minimal JSON object for an observe event.
# Usage: jsonl_observe_event <session_id> <phase> <tool> <args_json> <result_truncated>
jsonl_observe_event() {
  local session="$1" phase="$2" tool="$3" args="$4" result="$5"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","session":"%s","phase":"%s","tool":"%s","args":%s,"result":"%s"}' \
    "$ts" \
    "$(jsonl_escape "$session")" \
    "$(jsonl_escape "$phase")" \
    "$(jsonl_escape "$tool")" \
    "${args:-\"\"}" \
    "$(jsonl_truncate_escape "$result" 500)"
}
