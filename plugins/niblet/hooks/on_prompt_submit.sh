#!/usr/bin/env bash
# on_prompt_submit.sh — fires on UserPromptSubmit.
#
# Reads PENDING_FAST / PENDING_DEEP markers in <project>/.niblet/
# and emits the appropriate reminder to stdout. Claude / Kimi sees stdout
# as a system-reminder block prepended to the user's prompt.
#
# The agent is expected to act on the reminder (write files, spawn sub-agent)
# and then delete the marker file. The hook itself never modifies project files.

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/../lib/paths.sh" 2>/dev/null || exit 0

INPUT="$(cat 2>/dev/null || true)"
CWD="$(niblet_cwd_from_stdin "$INPUT")"
[ -z "$CWD" ] && CWD="$PWD"

PROJECT_ROOT="$(niblet_project_root "$CWD")"
STORE="$(niblet_store "$PROJECT_ROOT")"

# Nothing to do if there is no store yet.
[ -d "$STORE" ] || exit 0

PENDING_FAST="$STORE/PENDING_FAST"
PENDING_DEEP="$STORE/PENDING_DEEP"
COUNTER_FILE="$STORE/task_counter"
COUNT=0
[ -f "$COUNTER_FILE" ] && COUNT="$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)"

# Locate the latest raw log for this project, used by the deep sub-agent.
LATEST_RAW=""
if [ -d "$STORE/raw" ]; then
  LATEST_RAW="$(ls -t "$STORE/raw"/*.jsonl 2>/dev/null | head -n1)"
fi

# --- Determine artifact dirs (project scope) ---
KB_DIR="$(niblet_artifact_dir kb       project "$PROJECT_ROOT")"
SKILLS_DIR="$(niblet_artifact_dir skills   project "$PROJECT_ROOT")"
MEM_DIR="$(niblet_artifact_dir memory   project "$PROJECT_ROOT")"
CMD_DIR="$(niblet_artifact_dir commands project "$PROJECT_ROOT")"
GLOBAL_SKILLS_DIR="$(niblet_artifact_dir skills global "$PROJECT_ROOT")"

emit_fast() {
  cat <<EOF
NIBLET CHECKPOINT (fast)

A subtask just completed. Niblet — the project's crumb-keeper — wants you to
save what just mattered before you respond to the user. Do this:

1. Briefly review the previous turns. Decide if anything is worth keeping.
   Skip if the turns were trivial (only tool noise, no real findings).

2. If you discovered durable, non-obvious facts about THIS project
   (architecture, gotchas, "why X works this way", where a thing lives) →
   write or update files under:
       $KB_DIR/<topic>.md

3. If the user gave a correction or preference that should affect future work →
   write or update:
       $MEM_DIR/feedback_<short-slug>.md
   Lead with the rule, then "Why:" and "How to apply:" lines.

4. Prefer updating an existing file over creating a new one. One concept per file.
   Do NOT duplicate knowledge that is already there.

5. After writing (or deciding nothing is worth writing), delete the marker:
       rm $PENDING_FAST

6. Only then respond to the user's actual request.

This is mandatory. It is how this session compounds into permanent knowledge.
EOF
}

emit_deep() {
  cat <<EOF
NIBLET CHECKPOINT (deep)

The session has accumulated $COUNT completed subtasks (or has ended). Niblet
asks for a sub-agent to extract reusable workflow patterns — your active
context shouldn't be distracted by that analysis.

Before responding to the user, do this:

1. Use the Task / Agent tool to spawn a sub-agent (subagent_type=general-purpose)
   with the following prompt:

   ---
   You are the niblet-deep sub-agent. Your job is to extract reusable
   workflow patterns from a coding session and persist them as skills / commands.

   Inputs you have access to:
     - Session raw log:     $LATEST_RAW
     - Project KB:          $KB_DIR
     - Project skills:      $SKILLS_DIR
     - Project commands:    $CMD_DIR
     - Project root:        $PROJECT_ROOT

   Read the raw log and existing artifacts. Identify NEW workflow patterns —
   sequences of actions that solved a problem and would be reused next time.
   Do NOT duplicate patterns already covered by an existing skill.

   For each new pattern, output exactly one ACTION line, format:

     ACTION: ADD_KB_ENTRY   scope=project topic=<file>     content=<md>
     ACTION: CREATE_SKILL   scope=<p|g>   name=<name>      content=<md>
     ACTION: CREATE_COMMAND scope=<p|g>   name=<cmd>       content=<md>
     ACTION: UPDATE_CLAUDE  scope=project section=<head>   addition=<text>
     ACTION: NOTHING reason=<why> — if nothing worth noting.

     scope=global is reserved for patterns that are clearly cross-project
     (git, security, generic terminal workflows). Default to scope=project.

   For CREATE_SKILL / CREATE_COMMAND: include valid SKILL.md frontmatter.
   ---

2. After the sub-agent returns, apply each ACTION line by writing the file to
   the appropriate path:
     - CREATE_SKILL  scope=project → $SKILLS_DIR/<name>/SKILL.md
     - CREATE_SKILL  scope=global  → $GLOBAL_SKILLS_DIR/<name>/SKILL.md
     - ADD_KB_ENTRY                → $KB_DIR/<topic>.md
     - CREATE_COMMAND              → $CMD_DIR/<name>.md (or global home)
     - UPDATE_CLAUDE               → append to $PROJECT_ROOT/CLAUDE.md

3. Reset the task counter and delete markers:
       rm $PENDING_DEEP
       rm -f $PENDING_FAST
       printf 0 > $COUNTER_FILE

4. Only then respond to the user's actual request.

This is mandatory. The sub-agent has the bandwidth to think about patterns;
your main context should not be distracted by the analysis itself.
EOF
}

# Emit in priority order: deep first (covers fast), else fast.
if [ -f "$PENDING_DEEP" ]; then
  emit_deep
elif [ -f "$PENDING_FAST" ]; then
  emit_fast
fi

exit 0
