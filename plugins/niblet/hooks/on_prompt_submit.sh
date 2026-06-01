#!/usr/bin/env bash
# on_prompt_submit.sh — fires on UserPromptSubmit.
#
# Drains TWO sources:
#
#   1. Project-wide DEEP queue at <store>/pending_deep/*.queue. Any session
#      reading this queue can process work left behind by a previous
#      (possibly different) session. The reminder names the queue file and
#      its raw_log so the agent can spawn niblet-deep against the right log.
#
#   2. Current session's per-session PENDING_FAST. FAST findings are turn-
#      local — the agent still in the same session is the right writer.
#
# DEEP supersedes FAST in the same prompt. The reminder also tells the
# agent to use bin/niblet-apply and bin/niblet-promote — never direct
# Edit/Write to skills, commands, or CLAUDE.md.

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/../lib/store.sh" 2>/dev/null || exit 0

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
STORE="$(niblet_store "$PROJECT_ROOT")"
[ -d "$STORE" ] || exit 0

QUEUE_DIR="$STORE/pending_deep"
SESSION_DIR="$STORE/sessions/$SESSION"
PENDING_FAST="$SESSION_DIR/PENDING_FAST"

# User prompt text, when available, is checked for correction / negative
# feedback signals so the FAST checkpoint can be prioritized over DEEP/AUDIT.
USER_PROMPT="$(field prompt)"

# Returns 0 if the prompt contains an interruption signal, hard preference
# correction, or negative feedback trigger (case-insensitive, multilingual).
is_urgent_feedback() {
  local p="${1:-}"
  [ -n "$p" ] || return 1
  local lower
  lower="$(printf '%s' "$p" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *wtf*|\
    *"не так"*|\
    *"переделай"*|\
    *"стоп"*|\
    *"заново"*|\
    *"это бред"*|\
    *"ничего не работает"*|\
    *"никогда так не делай"*|\
    *"never do that"*|\
    *"never do this"*|\
    *"stop"*|\
    *"wrong"*|\
    *"incorrect"*|\
    *"reject"*|\
    *"revise"*|\
    *"отклоняю"*|\
    *"переделай план"*|\
    *"plan reject"*|\
    *"ctrl+c"*|\
    *"ctrl-c"*|\
    *"taskstop"*|\
    *"task stop"*)
      return 0
      ;;
  esac
  return 1
}
DISTILL_QUEUE_DIR="$STORE/distill_queue"
DISTILL_QUEUED_FLAG="$SESSION_DIR/DISTILL_QUEUED"
AUDIT_QUEUE_DIR="$STORE/audit_queue"

KB_DIR="$(niblet_artifact_dir kb       project "$PROJECT_ROOT")"
MEM_DIR="$(niblet_artifact_dir memory   project "$PROJECT_ROOT")"
PROPOSALS_DIR="$STORE/proposals"
GLOBAL_PROPOSALS_DIR="$HOME/.niblet-proposals"
# Bare command names — Claude Code adds each plugin's bin/ to the Bash tool
# PATH for hook / MCP / LSP subprocesses, so `niblet-apply` / `niblet-promote`
# resolve without an absolute path. Avoid printing ${CLAUDE_PLUGIN_ROOT} in
# reminders: it's an env var guaranteed only inside the plugin sandbox; the
# agent shouldn't rely on it expanding everywhere.

# Check KB size; if above threshold, write a distill queue entry at most once
# per session. Uses a per-session flag to avoid double-queuing.
_queue_distill_entry() {
  mkdir -p "$DISTILL_QUEUE_DIR" "$SESSION_DIR" 2>/dev/null
  local ts; ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local target="$DISTILL_QUEUE_DIR/${ts}.distill"
  # Write to a temp file then hard-link to the target name.
  # ln fails with EEXIST if the target already exists, eliminating the TOCTOU
  # race between the collision check and the write (same pattern as audit queue).
  local _tmp; _tmp="$(mktemp "$DISTILL_QUEUE_DIR/XXXXXXXX.tmp" 2>/dev/null)" \
    || _tmp="$DISTILL_QUEUE_DIR/.tmp-$$-${ts}"
  echo "session_id=$SESSION" > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return; }
  ln "$_tmp" "$target" 2>/dev/null || \
    ln "$_tmp" "${target%.distill}-$$.distill" 2>/dev/null || true
  rm -f "$_tmp"
  touch "$DISTILL_QUEUED_FLAG" 2>/dev/null || true
}

maybe_queue_distill() {
  [ -f "$DISTILL_QUEUED_FLAG" ] && return 0
  [ -d "$KB_DIR" ] || return 0
  local distill_count distill_bytes kb_count
  distill_count="${NIBLET_KB_DISTILL_COUNT:-20}"
  distill_bytes="${NIBLET_KB_DISTILL_BYTES:-200000}"
  kb_count="$(find "$KB_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$kb_count" -ge "$distill_count" ]; then
    _queue_distill_entry; return 0
  fi
  local kb_sz
  kb_sz="$(find "$KB_DIR" -maxdepth 1 -type f -exec wc -c {} + 2>/dev/null \
    | awk 'END{print ($1+0)}')"
  [ -z "$kb_sz" ] && kb_sz=0
  [ "$kb_sz" -ge "$distill_bytes" ] && _queue_distill_entry
}

maybe_queue_distill

# Sweep abandoned claims. A `.claimed-<session>` file means some prior session
# claimed a checkpoint but never finished it (e.g. the turn died on an API error).
# Such files litter the queue dirs and keep the proposal/queue status line nagging.
# Delete any older than NIBLET_CLAIM_STALE_HOURS (default 24h). Deleting (rather
# than re-queueing) is correct: a prior session already attempted the work, and
# on_session_end.sh only re-enqueues for sessions that did real work.
_sweep_stale_claims() {
  local hours mins
  hours="${NIBLET_CLAIM_STALE_HOURS:-24}"
  case "$hours" in *[!0-9]*) hours=24 ;; esac
  mins=$((hours * 60))
  local d
  for d in "$QUEUE_DIR" "$DISTILL_QUEUE_DIR" "$AUDIT_QUEUE_DIR"; do
    [ -d "$d" ] && find "$d" -maxdepth 1 -name '*.claimed-*' -type f -mmin "+$mins" -delete 2>/dev/null
  done
}
_sweep_stale_claims

# Atomically claim the oldest queue entry (FIFO) so two parallel new
# sessions cannot both pick the same DEEP job. We rename `.queue` to
# `.claimed-<session>` via `mv -n` (no-clobber); whoever wins the rename
# emits the reminder, the loser silently skips DEEP this round and tries
# the next oldest on the next prompt.
QUEUE_FILE=""
QUEUE_SIZE=0
if [ -d "$QUEUE_DIR" ]; then
  QUEUE_SIZE="$(ls -1 "$QUEUE_DIR"/*.queue 2>/dev/null | wc -l | tr -d ' ')"
  CANDIDATE="$(ls -1 "$QUEUE_DIR"/*.queue 2>/dev/null | sort | head -n1)"
  if [ -n "$CANDIDATE" ] && [ -f "$CANDIDATE" ]; then
    CLAIMED="${CANDIDATE%.queue}.claimed-$SESSION"
    if mv -n "$CANDIDATE" "$CLAIMED" 2>/dev/null && [ -f "$CLAIMED" ]; then
      QUEUE_FILE="$CLAIMED"
    fi
  fi
fi

# Atomically claim the oldest distill queue entry (same mv -n pattern).
DISTILL_FILE=""
DISTILL_SIZE=0
if [ -d "$DISTILL_QUEUE_DIR" ]; then
  DISTILL_SIZE="$(ls -1 "$DISTILL_QUEUE_DIR"/*.distill 2>/dev/null | wc -l | tr -d ' ')"
  DISTILL_CAND="$(ls -1 "$DISTILL_QUEUE_DIR"/*.distill 2>/dev/null | sort | head -n1)"
  if [ -n "$DISTILL_CAND" ] && [ -f "$DISTILL_CAND" ]; then
    DISTILL_CLAIMED="${DISTILL_CAND%.distill}.claimed-$SESSION"
    if mv -n "$DISTILL_CAND" "$DISTILL_CLAIMED" 2>/dev/null && [ -f "$DISTILL_CLAIMED" ]; then
      DISTILL_FILE="$DISTILL_CLAIMED"
    fi
  fi
fi

# Atomically claim the oldest audit queue entry (same mv -n pattern).
AUDIT_FILE=""
AUDIT_SIZE=0
if [ -d "$AUDIT_QUEUE_DIR" ]; then
  AUDIT_SIZE="$(ls -1 "$AUDIT_QUEUE_DIR"/*.audit 2>/dev/null | wc -l | tr -d ' ')"
  AUDIT_CAND="$(ls -1 "$AUDIT_QUEUE_DIR"/*.audit 2>/dev/null | sort | head -n1)"
  if [ -n "$AUDIT_CAND" ] && [ -f "$AUDIT_CAND" ]; then
    AUDIT_CLAIMED="${AUDIT_CAND%.audit}.claimed-$SESSION"
    if mv -n "$AUDIT_CAND" "$AUDIT_CLAIMED" 2>/dev/null && [ -f "$AUDIT_CLAIMED" ]; then
      AUDIT_FILE="$AUDIT_CLAIMED"
    fi
  fi
fi

# If the user just sent a correction or negative feedback, make sure we
# surface the FAST checkpoint immediately so the agent captures it before
# any background DEEP/AUDIT/DISTILL work.
URGENT_FAST=0
if is_urgent_feedback "$USER_PROMPT"; then
  URGENT_FAST=1
  mkdir -p "$SESSION_DIR" 2>/dev/null
  touch "$PENDING_FAST" 2>/dev/null || true
fi

# Pending proposal counts for the gentle nudge in every reminder.
proposal_status_line() {
  local p_count=0 g_count=0
  [ -d "$PROPOSALS_DIR" ] && p_count="$(find "$PROPOSALS_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ -d "$GLOBAL_PROPOSALS_DIR" ] && g_count="$(find "$GLOBAL_PROPOSALS_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$p_count" != "0" ] || [ "$g_count" != "0" ]; then
    printf '\n[Niblet] %s project proposal(s) in %s, %s global in %s.\n' \
      "$p_count" "$PROPOSALS_DIR" "$g_count" "$GLOBAL_PROPOSALS_DIR"
    printf 'Review each and promote with: niblet-promote <proposal-file>\n'
  fi
}

emit_fast() {
  local urgent="${1:-0}"
  local urgency_note=""
  if [ "$urgent" = "1" ]; then
    urgency_note="
URGENT — the user's message looks like a correction, interruption signal, or negative feedback.
BEFORE answering them, capture the exact correction as UPDATE_MEMORY (feedback_interruptions.md or feedback_wtf.md). Then continue with their request. Do not narrate the capture."
  fi
  cat <<EOF
NIBLET CHECKPOINT (fast) — session $SESSION$urgency_note

Background bookkeeping — NON-BLOCKING. First fully handle the user's request.
This is an auto-write tier (safe, local, reversible) note-to-self; it must never
delay, replace, or precede the user's actual task. Do everything below QUIETLY —
do not narrate it and never paste raw JSON action bodies into your reply to the
user. After you've handled the user (or right away if there's nothing to answer),
optionally do the following.

1. Briefly review the turn. Skip if trivial (chit-chat, formatting only). If
   there's nothing worth keeping, or you're mid-task and unsure, just
   \`rm $PENDING_FAST\` and move on silently — no narration, no NOTHING file.

2. For findings about THIS project (architecture, gotchas, "why X works
   this way", where a thing lives) → build an ADD_KB_ENTRY ACTION as
   a JSON object and feed it to the secure writer via stdin.

   Step a (Write tool): write the JSON to a staging file. The Write tool
   does NOT shell-interpret content, so any quote or metachar in your
   content is safe:

       Write file_path=$STORE/inbox/kb-<slug>.json
       Content:
         {"action":"ADD_KB_ENTRY","scope":"project","topic":"<slug>.md","content":"<markdown>"}

   Step b (Bash tool): pipe the file into niblet-apply:

       niblet-apply --project-root "$PROJECT_ROOT" < $STORE/inbox/kb-<slug>.json

   The script validates the slug, checks containment, and writes to:
       $KB_DIR/<slug>.md

3. For user corrections / preferences that should outlive this session →
   same pattern with UPDATE_MEMORY:

       Write file_path=$STORE/inbox/mem-<slug>.json
       Content:
         {"action":"UPDATE_MEMORY","scope":"project","file":"feedback_<slug>.md","content":"<markdown>"}

       niblet-apply --project-root "$PROJECT_ROOT" < $STORE/inbox/mem-<slug>.json

   Writes to: $MEM_DIR/feedback_<slug>.md

4. Never \`echo '<json>' | niblet-apply\`. The content field can carry
   single quotes and shell metachars; the echo would interpolate them on
   the command line BEFORE the script validates. Always Write-then-stdin.

5. Do NOT use Edit/Write directly to KB/memory/skills/commands — niblet-apply
   is the only safe path. It enforces slug rules and prevents writes
   outside the artifact dirs.

6. Do NOT create skills, commands, or modify CLAUDE.md here. Those happen
   in the DEEP checkpoint and only as proposals.

7. After writing (or deciding nothing is worth keeping), delete the marker:
       rm $PENDING_FAST

8. Return to (or continue with) the user's actual request. If you already
   answered it, you're done — do not announce the checkpoint.
$(proposal_status_line)
EOF
}

emit_deep() {
  # Read queue entry payload (safe: known key=value format, single-line values).
  local q_session q_raw q_turns
  q_session="$(grep -E '^session_id=' "$QUEUE_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)"
  q_raw="$(    grep -E '^raw_log='    "$QUEUE_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)"
  q_turns="$(  grep -E '^turns='      "$QUEUE_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)"
  [ -f "$q_raw" ] || q_raw="(no tool calls were captured for that session)"

  cat <<EOF
NIBLET CHECKPOINT (deep) — queue size $QUEUE_SIZE, processing $(basename "$QUEUE_FILE")

A previous session ended. Niblet asks you to spawn a sub-agent to extract
reusable workflow patterns from its raw log. Your active context shouldn't
be distracted by that analysis.

Background bookkeeping — NON-BLOCKING. FIRST fully handle the user's request,
THEN (only if it doesn't delay them) process this. If you're mid-task or unsure,
just \`rm $QUEUE_FILE\` and skip — a future session will not re-create it.
Do all of this QUIETLY: never paste raw JSON action bodies into your reply, and
if the analysis yields only NOTHING, silently \`rm $QUEUE_FILE\` without writing
a NOTHING file and without narrating it to the user.

Fast skip: if the raw log "$q_raw" is absent or shows fewer than
${NIBLET_DEEP_MIN_TOOLCALLS:-8} tool calls, there is nothing to extract — just
\`rm $QUEUE_FILE\` and return to the user.

When you do process it:

1. Use the Task / Agent tool with subagent_type=general-purpose and the
   following prompt verbatim:

   ---
   You are the niblet-deep sub-agent. Extract reusable workflow patterns
   from a coding session.

   Inputs (read-only metadata only — tool_input/tool_response content was
   NOT captured; you have tool name, file path, and exit code per event):
     - Session id:        $q_session
     - Raw session log:   $q_raw
     - Project KB:        $KB_DIR
     - Project root:      $PROJECT_ROOT
     - Turns observed:    $q_turns

   Identify NEW patterns. Do not duplicate what is already in the KB.

   Output STRICTLY one JSON object per line between the sentinels.
   No prose outside the sentinels.

       <<<NIBLET ACTIONS BEGIN>>>
       {"action":"<ACTION>", ...fields...}
       <<<NIBLET ACTIONS END>>>

   Allowed actions (all values are JSON strings; newlines in content as \\n):
     - {"action":"ADD_KB_ENTRY","scope":"project","topic":"<slug>.md","content":"<md>"}
     - {"action":"MERGE_KB_ENTRY","scope":"project","topic":"<slug>.md","content":"<md>","reason":"<why>"}
     - {"action":"UPDATE_KB_ENTRY","scope":"project","topic":"<slug>.md","content":"<md>","reason":"<why>"}
     - {"action":"DEPRECATE_KB_ENTRY","scope":"project","topic":"<slug>.md","reason":"<why>"}
     - {"action":"UPDATE_MEMORY","scope":"project","file":"<slug>.md","content":"<md>"}
     - {"action":"CREATE_SKILL","scope":"project|global","name":"<slug>","content":"<full SKILL.md>"}
     - {"action":"CREATE_AGENT","scope":"project|global","name":"<slug>","content":"<agent .md>"}
     - {"action":"CREATE_COMMAND","scope":"project|global","name":"<slug>","content":"<md>"}
     - {"action":"CREATE_SCRIPT","scope":"project|global","name":"<slug>","content":"<bash or python>"}
     - {"action":"UPDATE_SKILL","scope":"project|global","name":"<slug>","content":"<full SKILL.md>"}
     - {"action":"UPDATE_AGENT","scope":"project|global","name":"<slug>","content":"<agent .md>"}
     - {"action":"UPDATE_COMMAND","scope":"project|global","name":"<slug>","content":"<md>"}
     - {"action":"UPDATE_SCRIPT","scope":"project|global","name":"<slug>","content":"<script>"}
     - {"action":"UPDATE_CLAUDE","scope":"project","section":"<heading>","addition":"<text>"}
     - {"action":"OPEN_QUESTION","scope":"project","content":"<question>"}
     - {"action":"AUDIT_REPORT","scope":"project","content":"<findings>"}
     - {"action":"NOTHING","reason":"<one sentence>"}

   Slugs are: 1..64 chars, [a-z0-9][a-z0-9._-]*. No slashes, no "..".

   Use scope=global only for patterns clearly universal across projects
   (git, security, generic terminal idioms). Default scope=project.
   ---

2. Parse the lines between the sentinels. For EACH JSON object, stage it
   via Write to a per-action file under $STORE/inbox/ and pipe THAT file
   into niblet-apply — do NOT \`echo '<json>' | …\`. ACTION content can
   carry single quotes and shell metachars; echo would interpolate them
   before validation. Do NOT use Edit/Write directly to the target tree.

       Write file_path=$STORE/inbox/<random>.json   (the JSON object)
       niblet-apply --project-root "$PROJECT_ROOT" < $STORE/inbox/<random>.json

   The script validates slugs, enforces containment, and routes:
     - ADD_KB_ENTRY/UPDATE_KB_ENTRY/MERGE_KB_ENTRY/DEPRECATE_KB_ENTRY/UPDATE_MEMORY scope=project → auto-write
     - everything else (skills, commands, CLAUDE, any global) → proposal
   Anything that fails slug or containment check lands as a proposal with
   "rejected_reason" so you can see what was attempted.

3. Delete the processed queue entry:
       rm $QUEUE_FILE

4. Only if something was actually applied or proposed, mention it in one short
   line (with the proposals dir path). If everything was NOTHING, say nothing —
   just return to the user's request.
$(proposal_status_line)
EOF
}

emit_distill() {
  cat <<EOF
NIBLET CHECKPOINT (distill) — queue size $DISTILL_SIZE, processing $(basename "$DISTILL_FILE")

The project KB has grown above the distill threshold. Niblet asks you to spawn
a sub-agent to consolidate redundant or overlapping KB entries.

Background bookkeeping — NON-BLOCKING. FIRST fully handle the user's request,
THEN (only if it doesn't delay them) process this. If you're mid-task or unsure,
just \`rm $DISTILL_FILE\` and skip. Do it QUIETLY: never paste raw JSON action
bodies into your reply, and if the result is only NOTHING, silently
\`rm $DISTILL_FILE\` without writing a NOTHING file or narrating it.

When you do process it:

1. Use the Task / Agent tool with subagent_type=general-purpose and the
   following prompt verbatim:

   ---
   You are the niblet-distill sub-agent. Consolidate and deduplicate
   knowledge-base entries for this project.

   Inputs:
     - KB directory:      $KB_DIR
     - Memory directory:  $MEM_DIR
     - Digests directory: $STORE/digests
     - Project root:      $PROJECT_ROOT

   Read all files in the KB and memory directories. Identify duplicate or
   overlapping entries, stale topics, and patterns that recur across 3+
   digest sessions (suggesting a new skill or command).

   Output STRICTLY one JSON object per line between the sentinels.
   No prose outside the sentinels. Emit at most 5 actions.

       <<<NIBLET ACTIONS BEGIN>>>
       {"action":"<ACTION>", ...fields...}
       <<<NIBLET ACTIONS END>>>

   Allowed actions (all values are JSON strings; newlines in content as \\n):
     - {"action":"MERGE_KB_ENTRY","scope":"project","topic":"<slug>.md","content":"<md>","reason":"<why>"}
     - {"action":"UPDATE_KB_ENTRY","scope":"project","topic":"<slug>.md","content":"<md>","reason":"<why>"}
     - {"action":"DEPRECATE_KB_ENTRY","scope":"project","topic":"<slug>.md","reason":"<why>"}
     - {"action":"CREATE_SKILL","scope":"project","name":"<slug>","content":"<SKILL.md>","reason":"<why>"}
     - {"action":"CREATE_AGENT","scope":"project","name":"<slug>","content":"<agent.md>","reason":"<why>"}
     - {"action":"CREATE_COMMAND","scope":"project","name":"<slug>","content":"<md>","reason":"<why>"}
     - {"action":"NOTHING","reason":"<one sentence>"}

   Slugs: 1..64 chars, [a-z0-9][a-z0-9._-]*. No slashes, no "..".
   Use scope=global only for universal patterns (git, security, terminal idioms).
   ---

2. Parse the lines between the sentinels. For EACH JSON object, stage it
   via Write to a per-action file under $STORE/inbox/ and pipe THAT file
   into niblet-apply — do NOT \`echo '<json>' | …\`:

       Write file_path=$STORE/inbox/<random>.json   (the JSON object)
       niblet-apply --project-root "$PROJECT_ROOT" < $STORE/inbox/<random>.json

   The script validates slugs, enforces containment, and routes:
     - MERGE_KB_ENTRY/UPDATE_KB_ENTRY scope=project  → auto-write
     - DEPRECATE_KB_ENTRY scope=project              → auto-write
     - everything else (CREATE_*, any global)        → proposal

3. Delete the processed distill entry:
       rm $DISTILL_FILE

4. Only if something was actually merged, deprecated, or proposed, mention it in
   one short line (with the proposals dir path). If everything was NOTHING, say
   nothing — just return to the user's request.
$(proposal_status_line)
EOF
}

emit_audit() {
  cat <<EOF
NIBLET CHECKPOINT (audit) — queue size $AUDIT_SIZE, processing $(basename "$AUDIT_FILE")

Niblet is running a periodic artifact audit — checking KB, memory, and the
artifact index for staleness or contradictions.

Background bookkeeping — NON-BLOCKING. FIRST fully handle the user's request,
THEN (only if it doesn't delay them) process this. If you're mid-task or unsure,
just \`rm $AUDIT_FILE\` and skip. Do it QUIETLY: never paste raw JSON action
bodies into your reply, and if the result is only NOTHING, silently
\`rm $AUDIT_FILE\` without writing a NOTHING file or narrating it.

When you do process it:

1. Use the Task / Agent tool with subagent_type=general-purpose and the
   following prompt verbatim:

   ---
   You are the niblet-audit sub-agent. Audit this project's niblet artifacts
   for staleness, contradictions, and quality issues.

   Inputs:
     - Artifact index:    $STORE/index/artifacts.jsonl  (filenames only)
     - KB directory:      $KB_DIR
     - Memory directory:  $MEM_DIR
     - Digests directory: $STORE/digests
     - Project root:      $PROJECT_ROOT

   Read the artifact index to know what skills/agents/commands/scripts exist.
   Read KB and memory files. Read recent digests (if any).

   Identify issues:
   - KB entries referencing non-existent commands, paths, or artifacts
   - Artifacts in the index not referenced by any KB entry (potentially stale)
   - Contradictions between KB entries or between KB and memory
   - Duplicate artifacts with overlapping purpose

   Emit at most 5 actions per pass. Include evidence and confidence for each.

   Output STRICTLY one JSON object per line between the sentinels.
   No prose outside the sentinels.

       <<<NIBLET ACTIONS BEGIN>>>
       {"action":"<ACTION>", ...fields...}
       <<<NIBLET ACTIONS END>>>

   Allowed actions (all values are JSON strings; newlines in content as \\n):
     - {"action":"UPDATE_KB_ENTRY","scope":"project","topic":"<slug>.md","content":"<md>","evidence":"<why>","confidence":"high|medium|low"}
     - {"action":"DEPRECATE_KB_ENTRY","scope":"project","topic":"<slug>.md","reason":"<why>","evidence":"<why>","confidence":"high|medium|low"}
     - {"action":"UPDATE_SKILL","scope":"project","name":"<slug>","content":"<SKILL.md>","evidence":"<why>","confidence":"high|medium|low"}
     - {"action":"AUDIT_REPORT","scope":"project","content":"<findings summary>","evidence":"<details>","confidence":"high|medium|low"}
     - {"action":"OPEN_QUESTION","scope":"project","content":"<question for human>"}
     - {"action":"NOTHING","reason":"<one sentence>"}

   Slugs: 1..64 chars, [a-z0-9][a-z0-9._-]*. No slashes, no "..".
   ---

2. Parse the lines between the sentinels. For EACH JSON object, stage it
   via Write to a per-action file under $STORE/inbox/ and pipe THAT file
   into niblet-apply — do NOT \`echo '<json>' | …\`:

       Write file_path=$STORE/inbox/<random>.json   (the JSON object)
       niblet-apply --project-root "$PROJECT_ROOT" < $STORE/inbox/<random>.json

   The script validates slugs, enforces containment, and routes:
     - UPDATE_KB_ENTRY/DEPRECATE_KB_ENTRY scope=project  → auto-write
     - UPDATE_SKILL, AUDIT_REPORT, OPEN_QUESTION         → proposal

3. Delete the processed audit entry:
       rm $AUDIT_FILE

4. Only if something was actually updated, deprecated, or proposed, mention it in
   one short line (with the proposals dir path). If everything was NOTHING, say
   nothing — just return to the user's request.
$(proposal_status_line)
EOF
}

# Drain order:
#   1. URGENT FAST — user correction / negative feedback / interruption signal.
#   2. DEEP > AUDIT > DISTILL > FAST (normal background order).
# When a higher-priority entry wins, release any claimed lower-priority entries
# back to their queues so a future session can pick them up (prevents stranding).
if [ "$URGENT_FAST" = "1" ] && [ -f "$PENDING_FAST" ]; then
  # User feedback is time-sensitive; capture it before any background work.
  [ -n "$QUEUE_FILE" ]   && [ -f "$QUEUE_FILE" ]   && mv "$QUEUE_FILE"   "$CANDIDATE"   2>/dev/null || true
  [ -n "$DISTILL_FILE" ] && [ -f "$DISTILL_FILE" ] && mv "$DISTILL_FILE" "$DISTILL_CAND" 2>/dev/null || true
  [ -n "$AUDIT_FILE"   ] && [ -f "$AUDIT_FILE" ]   && mv "$AUDIT_FILE"   "$AUDIT_CAND"   2>/dev/null || true
  emit_fast 1
elif [ -n "$QUEUE_FILE" ] && [ -f "$QUEUE_FILE" ]; then
  [ -n "$DISTILL_FILE" ] && [ -f "$DISTILL_FILE" ] && mv "$DISTILL_FILE" "$DISTILL_CAND" 2>/dev/null || true
  [ -n "$AUDIT_FILE"   ] && [ -f "$AUDIT_FILE"   ] && mv "$AUDIT_FILE"   "$AUDIT_CAND"   2>/dev/null || true
  emit_deep
elif [ -n "$AUDIT_FILE" ] && [ -f "$AUDIT_FILE" ]; then
  [ -n "$DISTILL_FILE" ] && [ -f "$DISTILL_FILE" ] && mv "$DISTILL_FILE" "$DISTILL_CAND" 2>/dev/null || true
  emit_audit
elif [ -n "$DISTILL_FILE" ] && [ -f "$DISTILL_FILE" ]; then
  emit_distill
elif [ -f "$PENDING_FAST" ]; then
  emit_fast
fi

exit 0
