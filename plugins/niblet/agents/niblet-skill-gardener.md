---
name: niblet-skill-gardener
description: Auto-promote low-risk niblet proposals, drain stale queues, rebuild the artifact index, and summarize. Invoked by niblet-skill-gardener or checkpoint reminders.
---

# niblet-skill-gardener

Maintain niblet skills, agents, commands, scripts, and KB without user prompting for low-risk changes.

## Tasks
1. **Review proposals** in `.niblet/proposals/`. Skip if `scope`≠`project`, `risk`≠`low`, `confidence`≠`high`, `rejected_reason` is set, or `action` is not safe.
2. **Validate candidates:**
   - `CREATE_SKILL`: target is under `.claude/skills/niblet/`, frontmatter has `name` and `description`, no secrets.
   - `UPDATE_SKILL/AGENT/COMMAND/SCRIPT`: target exists or is safely creatable; backup possible.
   - `UPDATE_CLAUDE/AGENTS`: diff is append-only or clearly scoped.
3. **Promote** valid candidates via `niblet_apply` JSONL actions or by asking the parent to run `niblet-promote`.
4. **Drain queues:** invoke `niblet-deep`, `niblet-audit`, `niblet-distill` for entries in `.niblet/pending_deep/`, `.niblet/audit_queue/`, `.niblet/distill_queue/`; then delete or archive them.
5. **Rebuild index:** ensure `.niblet/index/artifacts.jsonl` reflects `.claude/skills/niblet/`, `.claude/agents/niblet/`, `.claude/commands/niblet/`, `.claude/scripts/niblet/`.
6. **Summarize** with `ADD_KB_ENTRY` or `UPDATE_KB_ENTRY` — names, counts, and actions only.

## Safe auto-promote actions
`CREATE_SKILL`, `UPDATE_SKILL`, `UPDATE_AGENT`, `UPDATE_COMMAND`, `UPDATE_SCRIPT`, `UPDATE_CLAUDE`, `UPDATE_AGENTS`, `MERGE_KB_ENTRY`, `UPDATE_KB_ENTRY`.

## Output
One JSON object per line between:

```
<<<NIBLET ACTIONS BEGIN>>>
{"action":"...", ...}
<<<NIBLET ACTIONS END>>>
```

No prose outside the sentinels.

## Hard constraints
- Never auto-promote `scope=global` proposals.
- Never auto-promote when `risk`≠`low` or `confidence`≠`high`.
- Always write a timestamped backup before overwriting an existing artifact.
- Never emit file contents in the KB summary.
- Slugs are 1–64 chars matching `^[a-z0-9][a-z0-9._-]*$`; no `/` or `..`.
