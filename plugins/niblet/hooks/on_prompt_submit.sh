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

KB_DIR="$(niblet_artifact_dir kb       project "$PROJECT_ROOT")"
MEM_DIR="$(niblet_artifact_dir memory   project "$PROJECT_ROOT")"
PROPOSALS_DIR="$STORE/proposals"
GLOBAL_PROPOSALS_DIR="$HOME/.niblet-proposals"
# Bare command names — Claude Code adds each plugin's bin/ to the Bash tool
# PATH for hook / MCP / LSP subprocesses, so `niblet-apply` / `niblet-promote`
# resolve without an absolute path. Avoid printing ${CLAUDE_PLUGIN_ROOT} in
# reminders: it's an env var guaranteed only inside the plugin sandbox; the
# agent shouldn't rely on it expanding everywhere.

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
  cat <<EOF
NIBLET CHECKPOINT (fast) — session $SESSION

A turn just ended. Niblet asks you to save anything worth keeping before
responding to the user. Auto-write tier — safe, local, reversible.

1. Briefly review the turn. Skip if trivial (chit-chat, formatting only).

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

8. Now respond to the user's actual request.
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

Before responding to the user, do this:

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
     - {"action":"UPDATE_MEMORY","scope":"project|global","file":"<slug>.md","content":"<md>"}
     - {"action":"CREATE_SKILL","scope":"project|global","name":"<slug>","content":"<full SKILL.md>"}
     - {"action":"CREATE_COMMAND","scope":"project|global","name":"<slug>","content":"<md>"}
     - {"action":"UPDATE_CLAUDE","scope":"project","section":"<heading>","addition":"<text>"}
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
     - ADD_KB_ENTRY/UPDATE_MEMORY scope=project   → auto-write
     - everything else (skills, commands, CLAUDE, any global) → proposal
   Anything that fails slug or containment check lands as a proposal with
   "rejected_reason" so you can see what was attempted.

3. Delete the processed queue entry:
       rm $QUEUE_FILE

4. Tell the user briefly what was applied vs proposed, including the
   proposals directory path so they can review. Then respond to their
   actual request.
$(proposal_status_line)
EOF
}

# Drain DEEP queue first; only fall back to FAST when queue is empty.
if [ -n "$QUEUE_FILE" ] && [ -f "$QUEUE_FILE" ]; then
  emit_deep
elif [ -f "$PENDING_FAST" ]; then
  emit_fast
fi

exit 0
