---
name: niblet-distill
description: Use when the user types /niblet-distill or when niblet-compact/niblet-wrap-up reports thresholds exceeded.
user-invocable: true
---

# /niblet-distill

## Overview

Run the niblet-distill consolidation sub-agent to deduplicate and compress the project's KB, memory, skills, agents, and commands.

## When to use

- User types `/niblet-distill`.
- User asks to run niblet-distill manually.
- After `niblet-compact` or `niblet-wrap-up` reports thresholds exceeded.

## Steps

1. Determine `PROJECT_ROOT`:
   - Start from the current working directory.
   - If inside a git repository, use `git rev-parse --show-toplevel`.
   - Otherwise use the current working directory.
2. Spawn a coder subagent with the prompt in the **niblet-distill sub-agent prompt** section below, passing:
   - Project root: `PROJECT_ROOT`
   - KB directory: `$PROJECT_ROOT/.claude/kb/`
   - Memory directory: `$PROJECT_ROOT/.claude/memory/`
   - Digests directory: `$PROJECT_ROOT/.niblet/digests/`
   - Skills directory: `$PROJECT_ROOT/.claude/skills/`
   - Agents directory: `$PROJECT_ROOT/.claude/agents/`
   - Commands directory: `$PROJECT_ROOT/.claude/commands/`
3. The subagent returns a JSONL block of actions between `<<<NIBLET ACTIONS BEGIN>>>` and `<<<NIBLET ACTIONS END>>>`. Parse it.
4. For each parsed action, call the `niblet_apply` MCP tool with:
   ```json
   {
     "project_root": "PROJECT_ROOT",
     "action": { "action": "...", ... }
   }
   ```
   Call it once per action. Do not batch multiple actions into one call.
5. Report which actions were applied vs proposed. Do NOT write skills/agents/commands/CLAUDE.md directly.

## Safety

- Only emit/apply actions returned by the subagent.
- All writes go through the `niblet_apply` MCP tool.
- Do not auto-trigger this skill unless the user explicitly asked for distillation or a threshold checkpoint was reached.

## niblet-distill sub-agent prompt

You are a knowledge-base distiller. Find redundancy, outdated entries, and stable multi-session patterns, then emit a JSONL block of consolidation actions.

### Inputs

The parent prompt names these paths:

- **KB directory** — current KB entries (`.claude/kb/`)
- **Memory directory** — feedback/correction records (`.claude/memory/`)
- **Digests directory** — sanitized session summaries (`.niblet/digests/`)
- **Skills directory** — existing skill definitions (`.claude/skills/`)
- **Agents directory** — existing agent definitions (`.claude/agents/`)
- **Commands directory** — existing command definitions (`.claude/commands/`)
- **Project root**

### Method

1. Read all KB entries, skills, agents, commands, and scripts. Look for:
   - Same topic from different angles → `MERGE_KB_ENTRY`
   - Outdated/superseded/contradictory entries → `DEPRECATE_KB_ENTRY`
   - Sparse stubs that fit a richer peer → `UPDATE_KB_ENTRY`
   - Duplicate skills/agents/commands → `MERGE_SKILL` / `MERGE_AGENT` / `UPDATE_COMMAND`
   - Stable project-wide invariants → `UPDATE_CLAUDE`

2. Read digest history. Look for:
   - File clusters across 3+ sessions → likely a skill
   - Recurring commands → `CREATE_COMMAND`
   - Patterns with no KB entry → `MERGE_KB_ENTRY`

3. Read memory files. Recurring corrections need stronger KB entries or skills, not more memory files.

4. For each candidate, ask:
   - Would this reduce KB size while preserving coverage? If not, skip.
   - Is the result strictly better than the originals? If uncertain, skip.
   - Would a new skill/command replace 3+ future KB entries? If not, skip.

5. Emit at most 5 actions per pass.

6. Output **ONLY** a JSONL block between the sentinels. No prose, no preamble.

### Output format

```
<<<NIBLET ACTIONS BEGIN>>>
{"action": "...", ...}
<<<NIBLET ACTIONS END>>>
```

One JSON object per line. All values are strings. Encode newlines inside `content` as `\n`.

### Consolidation rules

Be aggressive about shrinking the KB while preserving or improving coverage:

- Merge overlapping KB entries even if wording differs.
- Replace 2-3 related memory files with one concise KB entry or skill.
- Convert stable multi-session patterns into skills; do not leave them scattered as KB entries.
- Deprecate entries now covered by a skill or CLAUDE.md rule.
- If the same correction appears in memory 2+ times, make it a skill or CLAUDE.md rule.

Skill/agent/command checks:

- If two skills describe the same trigger/workflow, emit `UPDATE_SKILL` to merge them.
- If a skill references a removed file, outdated API, or obsolete convention, emit `UPDATE_SKILL` with corrected content or prepend a deprecation notice.
- If a KB entry is actually a reusable workflow, propose `CREATE_SKILL` and `DEPRECATE_KB_ENTRY`.
- If a skill is a one-off finding rather than reusable workflow, propose `ADD_KB_ENTRY` and `UPDATE_SKILL` with a deprecation notice.
- Apply the same logic to agents and commands using `MERGE_AGENT` / `UPDATE_AGENT` / `CREATE_COMMAND` / `UPDATE_COMMAND`.

Only propose changes when you have read the current artifact content and the evidence is strong.

### Allowed actions

| `action` | Required fields | Notes |
|---|---|---|
| `MERGE_KB_ENTRY` | `scope`, `topic`, `content`, `reason`, `confidence` | Merges/replaces an existing KB entry |
| `UPDATE_KB_ENTRY` | `scope`, `topic`, `content`, `reason`, `confidence` | Replaces a single KB entry |
| `DEPRECATE_KB_ENTRY` | `scope`, `topic`, `reason`, `confidence` | Marks entry deprecated |
| `CREATE_SKILL` | `scope`, `name`, `content`, `reason`, `confidence` | Only when stable across 3+ sessions |
| `UPDATE_SKILL` | `scope`, `name`, `content`, `reason`, `confidence` | Merge, correct, or deprecate an existing skill |
| `MERGE_SKILL` | `scope`, `name`, `content`, `reason`, `confidence` | Combine two skills into one; overwrites target |
| `CREATE_AGENT` | `scope`, `name`, `content`, `reason`, `confidence` | Only when sub-agent pattern is reused |
| `UPDATE_AGENT` | `scope`, `name`, `content`, `reason`, `confidence` | Merge, correct, or deprecate an existing agent |
| `MERGE_AGENT` | `scope`, `name`, `content`, `reason`, `confidence` | Combine two agents into one; overwrites target |
| `CREATE_COMMAND` | `scope`, `name`, `content`, `reason`, `confidence` | Only when command is repeated across sessions |
| `UPDATE_COMMAND` | `scope`, `name`, `content`, `reason`, `confidence` | Correct or deprecate an existing command |
| `UPDATE_CLAUDE` | `section`, `addition`, `reason`, `confidence` | Project-wide invariant to append to CLAUDE.md |
| `NOTHING` | `reason`, `confidence` | Valid when no consolidation is needed |

All actions must include `reason` (one sentence) and `confidence`. `beginner_summary` is optional.

### Scope rules

- `scope: "project"` — **Default.** Pattern is specific to this project.
- `scope: "global"` — Universal across any project (git/security/terminal idioms only).

### Slug constraints

`name` and `topic` are strict slugs: 1..64 chars, `^[a-z0-9][a-z0-9._-]*$`, no `/`, `\`, or `..`.

Do NOT invent fields like `source` or `target`.

### What NOT to emit

- More than 5 actions per pass.
- Actions that make the KB larger rather than smaller or sharper.
- `CREATE_SKILL`/`CREATE_AGENT`/`CREATE_COMMAND` that duplicate existing artifacts.
- `DEPRECATE_KB_ENTRY` without confirming the content is genuinely outdated.
- Anything derivable by reading the source code.

### Empty-distill output

```
<<<NIBLET ACTIONS BEGIN>>>
{"action": "NOTHING", "reason": "KB is well-structured; no consolidation needed at this time", "confidence": "high"}
<<<NIBLET ACTIONS END>>>
```
