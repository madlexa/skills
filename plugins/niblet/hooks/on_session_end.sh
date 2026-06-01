#!/usr/bin/env bash
# on_session_end.sh — fires on SessionEnd (session terminates).
#
# Writes a project-wide queue file so the NEXT session in this project picks
# up the DEEP checkpoint regardless of session_id. Per-session markers are
# unreachable across sessions because UserPromptSubmit only sees its own
# session_id — that bug was the original v0.2 P0 (the marker would be
# orphaned).
#
# Queue file:
#   <project>/.niblet/pending_deep/<utc-ts>-<ended-session-id>.queue
#
# Body (newline-delimited key=value):
#   session_id=<id>
#   raw_log=<absolute path to .jsonl>
#   turns=<count>
#   ended_at=<utc iso>
#
# Also writes:
#   .niblet/index/artifacts.jsonl  — filenames-only artifact index (never content)
#   .niblet/audit_queue/<ts>.audit — when session_count % NIBLET_AUDIT_INTERVAL_SESSIONS == 0

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/../lib/store.sh"  2>/dev/null || exit 0
. "$SCRIPT_DIR/../lib/digest.sh" 2>/dev/null || true

INPUT="$(cat 2>/dev/null || true)"

have_jq=0; command -v jq >/dev/null 2>&1 && have_jq=1
field() {
  local key="$1"
  if [ "$have_jq" = 1 ]; then
    printf '%s' "$INPUT" | jq -r ".${key} // empty" 2>/dev/null
  else
    printf '%s' "$INPUT" | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
  fi
}

CWD="$(field cwd)";            [ -z "$CWD" ]     && CWD="$PWD"
SESSION="$(field session_id)"; [ -z "$SESSION" ] && SESSION="unknown"

PROJECT_ROOT="$(niblet_project_root "$CWD")"
STORE="$(niblet_ensure_store "$PROJECT_ROOT" "$SESSION")"
[ -n "$STORE" ] || exit 0

QUEUE_DIR="$STORE/pending_deep"
mkdir -p "$QUEUE_DIR" 2>/dev/null

TS="$(date -u +%Y%m%dT%H%M%SZ)"
QUEUE_FILE="$QUEUE_DIR/${TS}-${SESSION}.queue"

# Look up turn count from per-session counter (best effort).
TURNS=0
COUNTER_FILE="$STORE/sessions/$SESSION/task_counter"
[ -f "$COUNTER_FILE" ] && TURNS="$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)"

# Gate: only enqueue a DEEP job when the session did real work. Trivial sessions
# (no/few tool calls — e.g. a session that just answered a question or processed a
# prior checkpoint) produce only NOTHING and otherwise make the queue self-
# perpetuating, hijacking the next session's first prompt. Count post-phase tool
# events in the raw log (same signal lib/digest.sh uses) and skip below the
# threshold. NIBLET_DEEP_MIN_TOOLCALLS=0 restores the old unconditional behavior.
RAW_LOG="$STORE/raw/${SESSION}.jsonl"
TOOLCALLS=0
[ -f "$RAW_LOG" ] && TOOLCALLS="$(grep -c '"phase":"post"' "$RAW_LOG" 2>/dev/null || echo 0)"
case "$TOOLCALLS" in *[!0-9]*) TOOLCALLS=0 ;; esac
DEEP_MIN_TC="${NIBLET_DEEP_MIN_TOOLCALLS:-8}"
case "$DEEP_MIN_TC" in *[!0-9]*) DEEP_MIN_TC=8 ;; esac

if [ "$TOOLCALLS" -ge "$DEEP_MIN_TC" ]; then
  {
    echo "session_id=$SESSION"
    echo "raw_log=$RAW_LOG"
    echo "turns=$TURNS"
    echo "ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$QUEUE_FILE" 2>/dev/null
fi
# Below threshold: no queue file written. Housekeeping below still runs.

# Write sanitized digest (safe metadata only — no raw content).
niblet_write_digest "$PROJECT_ROOT" "$SESSION" >/dev/null 2>&1 || true

# Increment per-project session count.
# mkdir is atomic on POSIX; use it as a portable advisory lock to serialize
# the read-modify-write when two sessions end concurrently.
# Retry up to 3 times (1 s pause each) so contending sessions don't silently
# drop their increment.
SESSION_COUNT_FILE="$STORE/session_count"
_sclock="${SESSION_COUNT_FILE}.lck"
_sclock_held=0
NEW_COUNT=0
_sc_attempts=3
while [ "$_sc_attempts" -gt 0 ]; do
  if mkdir "$_sclock" 2>/dev/null; then
    _sclock_held=1
    break
  fi
  _sc_attempts=$((_sc_attempts - 1))
  [ "$_sc_attempts" -gt 0 ] && sleep 1
done
if [ "$_sclock_held" = "1" ]; then
  COUNT=0
  if [ -f "$SESSION_COUNT_FILE" ]; then
    COUNT="$(cat "$SESSION_COUNT_FILE" 2>/dev/null || echo 0)"
    case "$COUNT" in *[!0-9]*) COUNT=0 ;; esac
  fi
  NEW_COUNT=$((COUNT + 1))
  echo "$NEW_COUNT" > "$SESSION_COUNT_FILE" 2>/dev/null || true
  rmdir "$_sclock" 2>/dev/null || true
fi

# Write artifact index: scan artifact dirs and record filenames only (never content).
_write_artifact_index() {
  local pr="$1" store="$2"
  local index_file="$store/index/artifacts.jsonl"
  mkdir -p "$store/index" 2>/dev/null
  local sd ad cmd_d scr_d
  sd="$(niblet_artifact_dir skills   project "$pr")"
  ad="$(niblet_artifact_dir agents   project "$pr")"
  cmd_d="$(niblet_artifact_dir commands project "$pr")"
  scr_d="$(niblet_artifact_dir scripts  project "$pr")"
  # Emit one JSON object per artifact. Use jq when available so that
  # artifact names with quotes or backslashes (shouldn't occur given slug
  # validation, but defensive) are encoded safely.
  _emit_artifact_json() {
    local _kind="$1" _name="$2"
    if [ "$have_jq" = "1" ]; then
      jq -cn --arg kind "$_kind" --arg name "$_name" '{kind: $kind, name: $name}'
    else
      printf '{"kind":"%s","name":"%s"}\n' "$_kind" "$_name"
    fi
  }
  {
    if [ -d "$sd" ]; then
      for d in "$sd"/*/; do
        [ -d "$d" ] && _emit_artifact_json "skills" "$(basename "$d")"
      done
    fi
    if [ -d "$ad" ]; then
      for f in "$ad"/*.md; do
        [ -f "$f" ] && _emit_artifact_json "agents" "$(basename "$f")"
      done
    fi
    if [ -d "$cmd_d" ]; then
      for f in "$cmd_d"/*.md; do
        [ -f "$f" ] && _emit_artifact_json "commands" "$(basename "$f")"
      done
    fi
    if [ -d "$scr_d" ]; then
      for f in "$scr_d"/*; do
        [ -f "$f" ] && _emit_artifact_json "scripts" "$(basename "$f")"
      done
    fi
  } > "$index_file" 2>/dev/null || true
}
_write_artifact_index "$PROJECT_ROOT" "$STORE"

# Trigger audit queue when session count reaches a multiple of the interval.
AUDIT_INTERVAL="${NIBLET_AUDIT_INTERVAL_SESSIONS:-5}"
AUDIT_QUEUE_DIR="$STORE/audit_queue"
mkdir -p "$AUDIT_QUEUE_DIR" 2>/dev/null
if [ "$_sclock_held" = "1" ] && [ "$AUDIT_INTERVAL" -gt 0 ] && [ $(( NEW_COUNT % AUDIT_INTERVAL )) -eq 0 ]; then
  AUDIT_TS="$(date -u +%Y%m%dT%H%M%SZ)"
  AUDIT_FILE_NEW="$AUDIT_QUEUE_DIR/${AUDIT_TS}.audit"
  # Write to a temp file then atomically link to the target name.
  # ln() fails with EEXIST if the target already exists, eliminating the
  # TOCTOU race between the collision check and the write.
  _tmp_audit="$(mktemp "$AUDIT_QUEUE_DIR/XXXXXXXX.tmp" 2>/dev/null)" || _tmp_audit="$AUDIT_QUEUE_DIR/.tmp-$$-${AUDIT_TS}"
  echo "session_id=$SESSION" > "$_tmp_audit" 2>/dev/null || true
  _ai=0
  _audit_linked=0
  while [ "$_ai" -lt 50 ]; do
    if ln "$_tmp_audit" "$AUDIT_FILE_NEW" 2>/dev/null; then
      rm -f "$_tmp_audit" 2>/dev/null || true
      _audit_linked=1
      break
    fi
    _ai=$((_ai+1))
    AUDIT_FILE_NEW="$AUDIT_QUEUE_DIR/${AUDIT_TS}-${_ai}.audit"
  done
  [ "$_audit_linked" = "0" ] && rm -f "$_tmp_audit" 2>/dev/null || true
fi

exit 0
