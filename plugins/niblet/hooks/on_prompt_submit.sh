#!/usr/bin/env bash
# on_prompt_submit.sh — fires on UserPromptSubmit.
#
# Reads PENDING_FAST / PENDING_DEEP markers from THIS session's dir
# (<project>/.niblet/sessions/<session_id>/) and emits the appropriate
# reminder to stdout. The agent sees stdout as a system-reminder block.
#
# v0.2 — two-tier write authority:
#   AUTO-WRITE (safe, project-local): ADD_KB_ENTRY, UPDATE_MEMORY (project)
#   PROPOSAL (everything else):       CREATE_SKILL, CREATE_COMMAND,
#                                     UPDATE_CLAUDE, any scope=global
#
# Proposals land in <project>/.niblet/proposals/ (project scope) or
# ~/.niblet-proposals/ (global scope). The user reviews and promotes
# manually via `mv`. The plugin never auto-writes anything that
# changes behavior across future sessions.

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

SESSION_DIR="$STORE/sessions/$SESSION"
[ -d "$SESSION_DIR" ] || exit 0

PENDING_FAST="$SESSION_DIR/PENDING_FAST"
PENDING_DEEP="$SESSION_DIR/PENDING_DEEP"
COUNTER_FILE="$SESSION_DIR/task_counter"
COUNT=0
[ -f "$COUNTER_FILE" ] && COUNT="$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)"

RAW_FILE="$STORE/raw/${SESSION}.jsonl"
[ -f "$RAW_FILE" ] || RAW_FILE="(no tool calls were observed for this session)"

# --- Artifact directories ---
KB_DIR="$(niblet_artifact_dir kb       project "$PROJECT_ROOT")"
MEM_DIR="$(niblet_artifact_dir memory   project "$PROJECT_ROOT")"
PROPOSALS_DIR="$STORE/proposals"
GLOBAL_PROPOSALS_DIR="$HOME/.niblet-proposals"

# Count pending proposals (project + global) for nudging the user.
proposal_status_line() {
  local p_count g_count
  p_count=0; g_count=0
  [ -d "$PROPOSALS_DIR" ] && p_count="$(find "$PROPOSALS_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ -d "$GLOBAL_PROPOSALS_DIR" ] && g_count="$(find "$GLOBAL_PROPOSALS_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$p_count" != "0" ] || [ "$g_count" != "0" ]; then
    printf '\n[Niblet] %s project proposal(s) in %s, %s global in %s. Review with: ls -lh, promote with: mv <file> <target>.\n' \
      "$p_count" "$PROPOSALS_DIR" "$g_count" "$GLOBAL_PROPOSALS_DIR"
  fi
}

emit_fast() {
  cat <<EOF
NIBLET CHECKPOINT (fast) — session $SESSION

The previous turn just ended. Niblet asks you to save anything worth keeping
before responding to the user. Auto-write tier — safe, local, reversible:

1. Briefly review the turn that just finished. Skip if it was trivial
   (chit-chat, formatting, no real findings).

2. If you discovered durable, non-obvious facts about THIS project
   (architecture, gotchas, "why X works this way", where a thing lives) →
   write or update under:
       $KB_DIR/<topic>.md

3. If the user gave a correction or preference that should outlive this
   session → write or update:
       $MEM_DIR/feedback_<short-slug>.md
   Lead with the rule, then "Why:" and "How to apply:" lines.

4. Prefer updating an existing file over creating a new one.
   Never duplicate a concept across files.

5. DO NOT create skills, commands, or modify CLAUDE.md here — those happen
   in the DEEP checkpoint and only as proposals the user reviews.

6. After writing (or deciding nothing is worth keeping), delete the marker:
       rm $PENDING_FAST

7. Only then respond to the user's actual request.

This is mandatory. It is how this session compounds into permanent knowledge.
$(proposal_status_line)
EOF
}

emit_deep() {
  cat <<EOF
NIBLET CHECKPOINT (deep) — session $SESSION, $COUNT turns

The session has ended (or hit the safety-net counter). Niblet asks for a
sub-agent to extract reusable workflow patterns. Your active context
shouldn't be distracted by that analysis.

Before responding to the user, do this:

1. Use the Task / Agent tool to spawn a sub-agent
   (subagent_type=general-purpose) with the following prompt:

   ---
   You are the niblet-deep sub-agent. Extract reusable workflow patterns
   from this coding session.

   Inputs (read-only metadata; tool_input/tool_response content was NOT
   captured — only tool name, file path, and exit code):
     - Session raw log:   $RAW_FILE
     - Project KB:        $KB_DIR
     - Project root:      $PROJECT_ROOT

   Identify NEW patterns — sequences of actions on paths that solved a
   problem and would be reused. Do not duplicate anything already in KB.

   Output STRICTLY one JSON object per line between the sentinels.
   No prose outside the sentinels.

   <<<NIBLET ACTIONS BEGIN>>>
   {"action":"<ACTION>", ...fields...}
   <<<NIBLET ACTIONS END>>>

   Allowed actions (all values are strings):
     - {"action":"ADD_KB_ENTRY","scope":"project","topic":"<file.md>","content":"<md>"}
     - {"action":"UPDATE_MEMORY","scope":"project|global","file":"<name>.md","content":"<md>"}
     - {"action":"CREATE_SKILL","scope":"project|global","name":"<kebab>","content":"<full SKILL.md>"}
     - {"action":"CREATE_COMMAND","scope":"project|global","name":"<cmd>","content":"<md>"}
     - {"action":"UPDATE_CLAUDE","scope":"project","section":"<heading>","addition":"<text>"}
     - {"action":"NOTHING","reason":"<one sentence>"}

   scope=global is for patterns clearly universal across projects.
   Default scope=project. CREATE_SKILL content is a full SKILL.md
   (frontmatter included). Newlines in content as \\\\n.
   ---

2. Parse the lines between the sentinels as JSONL. Route each action by
   risk level — DO NOT write skills/commands/CLAUDE.md or global anything
   to live paths. Use the proposals dir; the user promotes manually.

   action / scope                          target path
   -------------------------------------   --------------------------------------------------
   ADD_KB_ENTRY    project                 $KB_DIR/<topic>
   UPDATE_MEMORY   project                 $MEM_DIR/<file>
   --- everything below is a PROPOSAL ---  $PROPOSALS_DIR/<ts>-<slug>.md (project)
   --- or for scope=global ---             $GLOBAL_PROPOSALS_DIR/<ts>-<slug>.md
   CREATE_SKILL    *                       proposal — embed "target: <skills-dir>/<name>/SKILL.md"
   CREATE_COMMAND  *                       proposal — embed "target: <commands-dir>/<name>.md"
   UPDATE_CLAUDE   project                 proposal — embed "target: $PROJECT_ROOT/CLAUDE.md"
   UPDATE_MEMORY   global                  proposal — embed "target: ~/.claude/memory/<file>"
   ADD_KB_ENTRY    global                  proposal — embed "target: ~/.claude/kb/<topic>"
   NOTHING                                 skip

   Proposal file format:
     ---
     action: CREATE_SKILL
     scope: project
     target: <full target path>
     ---
     <content payload verbatim>

3. Reset session counters and delete markers:
       rm $PENDING_DEEP
       rm -f $PENDING_FAST
       printf 0 > $COUNTER_FILE

4. Tell the user briefly that N proposals are waiting in $PROPOSALS_DIR
   (and $GLOBAL_PROPOSALS_DIR if any global) and how to promote them
   (review then \`mv <proposal> <target>\`), THEN respond to their request.
$(proposal_status_line)
EOF
}

# DEEP supersedes FAST when both are pending.
if [ -f "$PENDING_DEEP" ]; then
  emit_deep
elif [ -f "$PENDING_FAST" ]; then
  emit_fast
fi

exit 0
