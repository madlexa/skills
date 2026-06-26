---
name: niblet-distill
description: Use when the user types /niblet-distill to consolidate and deduplicate the project's KB, memory, skills, agents, and commands.
---

# /niblet-distill

Run the niblet-distill consolidation sub-agent and route the resulting actions through `niblet-apply`.

## Steps

1. Determine `PROJECT_ROOT`:
   - Start from the current working directory.
   - If inside a git repository, use `git rev-parse --show-toplevel`.
   - Otherwise use the current working directory.
2. Read `${CLAUDE_PLUGIN_ROOT}/agents/niblet-distill.md`. This file contains the consolidation prompt.
3. Spawn a coder subagent with that prompt, passing:
   - Project root: `PROJECT_ROOT`
   - KB directory: `$PROJECT_ROOT/.claude/kb/`
   - Memory directory: `$PROJECT_ROOT/.claude/memory/`
   - Digests directory: `$PROJECT_ROOT/.niblet/digests/`
   - Skills directory: `$PROJECT_ROOT/.claude/skills/`
   - Agents directory: `$PROJECT_ROOT/.claude/agents/`
   - Commands directory: `$PROJECT_ROOT/.claude/commands/`
4. Parse the JSONL actions returned between `<<<NIBLET ACTIONS BEGIN>>>` and `<<<NIBLET ACTIONS END>>>`.
5. For each action, write it to a temporary JSON file and run:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/niblet-apply" --project-root "$PROJECT_ROOT" < <file>.json
   ```
6. Report which actions were applied vs proposed. Do NOT write skills/agents/commands/CLAUDE.md directly.

## Safety

- Only emit/apply actions returned by the subagent.
- All writes go through `niblet-apply`.
- If `${CLAUDE_PLUGIN_ROOT}` is not set, fail with a clear message telling the user to run the command from inside Claude Code with the niblet plugin installed.
