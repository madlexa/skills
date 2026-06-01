---
name: niblet
description: Project knowledge keeper. In Claude — reacts to NIBLET CHECKPOINT reminders. In Kimi Code CLI — use MCP tools explicitly after mutations/interruptions/negative feedback. All writes route through niblet-apply.
user-invocable: false
---

# niblet

Niblet captures discoveries, workflow patterns, and user feedback across AI coding sessions.

- **Claude Code**: hooks inject `NIBLET CHECKPOINT` reminders.
- **Kimi Code CLI**: no hooks — call `niblet_log`, `niblet_apply`, `niblet_status`, `niblet_promote` explicitly with `project_root`.

## Trust model

| Tier | Auto-write | Proposal |
|---|---|---|
| KB entries, memory, KB merge/update/deprecate | `.claude/kb/`, `.claude/memory/` | — |
| Skills, agents, commands, scripts, CLAUDE.md/AGENTS.md, global actions | — | `.niblet/proposals/` or `~/.niblet-proposals/` |

Skills and AGENTS.md affect every session and are checked into git — they require human review.

## Configuration (`.niblet/config`)

| Variable | Default | Purpose |
|---|---|---|
| `NIBLET_AUTO_PROMOTE` | `0` | Auto-promote low-risk/high-confidence project proposals. |
| `NIBLET_KB_DISTILL_COUNT` | `20` | KB file threshold for compact suggestion. |
| `NIBLET_KB_DISTILL_BYTES` | `200000` | KB byte threshold. |
| `NIBLET_ARTIFACT_COMPACT_COUNT` | `20` | Skill/agent/command/script count threshold. |
| `NIBLET_ARTIFACT_COMPACT_BYTES` | `200000` | Artifact byte threshold. |
| `NIBLET_MEMORY_COMPACT_COUNT` | `5` | Memory feedback threshold. |
| `NIBLET_AUDIT_INTERVAL_SESSIONS` | `5` | Sessions between AUDIT triggers (Claude). |
| `NIBLET_GUARDED_APPLY` | unset | Auto-promote low-risk KB merge/update proposals. |
| `NIBLET_BEGINNER_UX` | unset | Embed `beginner_summary` in proposals. |

## Action routing

| Action | Scope | Routing |
|---|---|---|
| `ADD_KB_ENTRY`, `MERGE_KB_ENTRY`, `UPDATE_KB_ENTRY`, `DEPRECATE_KB_ENTRY` | project | auto-write → `kb/<topic>.md` |
| `UPDATE_MEMORY` | project | append → `memory/<file>` |
| `CREATE_SKILL/AGENT/COMMAND/SCRIPT` | any | proposal |
| `UPDATE_SKILL/AGENT/COMMAND/SCRIPT`, `MERGE_SKILL/AGENT` | any | proposal with `.niblet-backup` |
| `UPDATE_CLAUDE`, `UPDATE_AGENTS` | project | proposal, appends to CLAUDE.md/AGENTS.md |
| `OPEN_QUESTION`, `AUDIT_REPORT` | any | proposal |
| unknown / bad slug / path escape | any | proposal with `rejected_reason` |

## File semantics

- `ADD_KB_ENTRY` → new file; fails to proposal if exists.
- `MERGE_KB_ENTRY` / `UPDATE_KB_ENTRY` → overwrite existing.
- `DEPRECATE_KB_ENTRY` → prepend marker.
- `UPDATE_MEMORY` → append, stripping duplicate frontmatter.
- `CREATE_*` → new artifact proposal.
- `UPDATE_*` / `MERGE_*` → overwrite with backup.
- `UPDATE_CLAUDE` / `UPDATE_AGENTS` → append section.

## Kimi-specific rules

### Always pass `project_root`

The MCP server runs inside the plugin install directory, not the project. Every call must include the absolute project root:

```json
{
  "project_root": "/abs/path/to/project",
  "action": { ... }
}
```

### Log every file mutation immediately

After `Write`, `Edit`, or file-mutating `Bash`, call `niblet_log`:

```json
{
  "project_root": "/abs/path/to/project",
  "session_id": "<id>",
  "tool": "WriteFile|Edit|Bash",
  "path": "src/main.py",
  "exit_code": "0",
  "success": true
}
```

For Bash, leave `path` empty and set `exit_code`.

### Capture interruptions and negative feedback first

If the user stops execution, rejects a plan, or sends a correction, immediately write `UPDATE_MEMORY` to `feedback_interruptions.md` or `feedback_wtf.md` before continuing. Use their exact words.

Negative signals (case-insensitive): `wtf`, `не так`, `переделай`, `стоп`, `заново`, `это бред`, `ничего не работает`, `никогда так не делай`, `never do that`.

### Capture rules as durable instructions

When the user says "always", "never", describes a pipeline step, or repeats a correction:
- Reusable workflow → `CREATE_SKILL`.
- Project-wide invariant/pipeline → `UPDATE_CLAUDE` / `UPDATE_AGENTS`.
- One-time correction → `UPDATE_MEMORY`.

### Trigger deep analysis at task end

Run `niblet-deep` automatically after:
- ≥ 8 file-mutating tool calls.
- User says "save findings" / "сохрани выводы".
- Code review/refactoring/negative-feedback exchange ends.

Procedure:
1. `niblet_status` with `project_root`.
2. Spawn `niblet-deep` with raw log path.
3. Route actions through `niblet_apply`.
4. Apply KB/memory actions immediately; leave proposals for review.
5. Run `niblet-wrap-up --project-root <project>` and report suggestions.
6. Delete or mark the raw log processed.

### Trigger code-walker

After reading/editing ~5+ files in one component, run `niblet-code-walker --project-root <project>` and update `.niblet/.code-walker-last-run`.

### End-of-task maintenance

`niblet-wrap-up` checks thresholds, gardener, queues, and code-walker freshness. If it suggests a sub-agent, propose the command to the user. Only auto-spawn when the user asks to save findings or a queued checkpoint exists.

### KB index on session start

List only filenames:
```bash
ls -1 <project>/.claude/kb/*.md 2>/dev/null
ls -1 <project>/.claude/memory/*.md 2>/dev/null
```

Never leak H1 or body content.

## Claude-specific rules

- **URGENT FAST** → capture feedback first, then answer.
- **FAST** → turn-local KB/memory writes only.
- **DEEP** → spawn `niblet-deep`, route actions, delete queue entry.
- **DISTILL** → spawn `niblet-distill`.
- **AUDIT** → spawn `niblet-audit`.

## Universal rules

- Route all KB/memory/skill/agent/command/script/CLAUDE.md/AGENTS.md writes through `niblet-apply`. Never `Edit`/`Write` them directly.
- Stage JSON to a file, then pipe via stdin: `niblet-apply --project-root <path> < <inbox>.json`. Never `echo '<json>' | niblet-apply`.
- Slugs: 1–64 chars, `^[a-z0-9][a-z0-9._-]*$`, no `/`, `\`, or `..`.
- Do not save: code derivable from source, step-by-step tool calls, apologies, in-progress state, secrets.

## Output formats

**KB entry**: `# Topic`, one-paragraph summary, `## Key facts`, optional `## Why`, `## Gotchas`.

**Memory feedback**: frontmatter `name`/`description`, then the rule, `**Why:**`, `**How to apply:**`.

**Skill proposal**: frontmatter `action`/`scope`/`target`, then a valid `SKILL.md` with `name`, `description`, `# Title`, `## When to use`, `## Steps`.
