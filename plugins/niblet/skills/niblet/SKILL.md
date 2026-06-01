---
name: niblet
description: Project knowledge keeper. In Claude — reacts to NIBLET CHECKPOINT reminders. In Kimi Code CLI — uses MCP tools to log events, capture user corrections after interruptions (Ctrl+C, TaskStop, plan reject), and surface "wtf" feedback so it never repeats. All writes go through niblet-apply (secure entry point).
user-invocable: false
---

# niblet

Niblet quietly captures discoveries, workflow patterns, and user feedback across AI coding sessions.

- **Claude Code**: hooks inject `NIBLET CHECKPOINT` reminders automatically.
- **Kimi Code CLI**: no hooks — use the four MCP tools (`niblet_log`, `niblet_apply`, `niblet_status`, `niblet_promote`) explicitly after file mutations, interruptions, and negative feedback.

## Trust model — two tiers of write authority

| Tier | What gets written | Where |
|---|---|---|
| **Auto-write** (safe, local, reversible) | KB entries, feedback memory | `<project>/.claude/kb/` or `.kimi/kb/`; `.claude/memory/` or `.kimi/memory/` |
| **Proposal** (needs user promotion) | Skills, agents, scripts, commands, AGENTS.md/CLAUDE.md edits, any `scope=global` | `<project>/.niblet/proposals/` or `~/.niblet-proposals/` |

The runtime auto-detects whether the active CLI is Claude or Kimi and resolves artifact paths accordingly (`.claude/` vs `.kimi/`).

### Action types and routing

| Action | Scope | Routing |
|---|---|---|
| `ADD_KB_ENTRY` | project | **auto-write** → `kb/<topic>.md` |
| `MERGE_KB_ENTRY` | project | **auto-write** → merged into `kb/<topic>.md` |
| `UPDATE_KB_ENTRY` | project | **auto-write** → overwrites `kb/<topic>.md` |
| `DEPRECATE_KB_ENTRY` | project | **auto-write** → prepends deprecation notice |
| `UPDATE_MEMORY` | project | **auto-write** → `memory/feedback_<slug>.md` |
| `CREATE_SKILL` | any | **proposal** |
| `CREATE_AGENT` | any | **proposal** |
| `CREATE_SCRIPT` | any | **proposal** (envelope includes validation result) |
| `CREATE_COMMAND` | any | **proposal** |
| `UPDATE_SKILL` | any | **proposal** (backup before overwrite on promotion) |
| `UPDATE_AGENT` | any | **proposal** (backup before overwrite) |
| `UPDATE_COMMAND` | any | **proposal** (backup before overwrite) |
| `UPDATE_SCRIPT` | any | **proposal** (backup before overwrite) |
| `UPDATE_CLAUDE` | project | **proposal** |
| `UPDATE_AGENTS` | project | **proposal** |
| `UPDATE_CLAUDE` / `UPDATE_AGENTS` | global | **proposal** |
| `OPEN_QUESTION` | any | **proposal** |
| `AUDIT_REPORT` | any | **proposal** |
| `ADD_KB_ENTRY` | global | **proposal** → `~/.niblet-proposals/` |
| `UPDATE_MEMORY` | global | **proposal** |
| unknown action | any | **proposal** with `rejected_reason` |
| bad slug or path escape | any | **proposal** with `rejected_reason` |

Why proposals: skills and AGENTS.md affect every future session and are checked into git. Auto-writing them would let any text the AI reads become a permanent committed instruction. Proposals require a human action to take effect.

---

## Kimi-specific rules (explicit MCP tool calls)

In Kimi Code CLI there are no automatic hooks. **You must call the niblet MCP tools yourself** following the rules below.

Available tools:
- `niblet_log` — append a sanitized event to the raw session log.
- `niblet_apply` — secure write entry point for all KB/memory/proposal actions.
- `niblet_status` — project dashboard (counts and paths only).
- `niblet_promote` — apply a reviewed proposal file.

### 1. ALWAYS log file mutations
After **every** `WriteFile`, `StrReplaceFile`, or `NotebookEdit` call, immediately invoke `niblet_log` with these arguments:

```json
{
  "session_id": "<current session id>",
  "tool": "WriteFile",
  "path": "src/main.py",
  "exit_code": "",
  "success": true
}
```

For `Bash` tools, also log but omit the command args (path stays empty):
```json
{
  "session_id": "<current session id>",
  "tool": "Bash",
  "path": "",
  "exit_code": "0",
  "success": true
}
```

This builds the raw session log so `niblet-deep` can extract patterns later.

### 2. IMMEDIATELY capture interruptions, corrections, and negative sentiment
Follow the **Universal rules → Capture interruptions and negative feedback immediately** section above. Call `niblet_apply` with `UPDATE_MEMORY` for `feedback_interruptions.md` or `feedback_wtf.md` before continuing with the user's request.

### 3. Session-end deep analysis
When the user says "save findings", "сохрани выводы", or the session is clearly wrapping up:

1. Call `niblet_status` to see the dashboard.
2. If the raw log has ≥ 8 tool calls, spawn a sub-agent with the `niblet-deep` skill/prompt and pass the raw log path.
3. Route the sub-agent's JSONL actions through `niblet_apply` one by one.
4. Delete the raw log or mark the session as processed (your choice — the store is in `<project>/.niblet/raw/`).

### 4. KB index on session start
At the **very beginning** of a Kimi session (before answering the user), read the KB directory and emit a compact index:

```bash
# Niblet writes to .kimi/ under Kimi Code CLI
ls -1 <project>/.kimi/kb/*.md 2>/dev/null
ls -1 <project>/.kimi/memory/*.md 2>/dev/null
```

List **only filenames** (no H1, no content) — same safety rule as the Claude SessionStart hook. This helps you know which topics are already covered.

---

## Claude-specific rules (hook-driven checkpoints)

When you see a `NIBLET CHECKPOINT` reminder injected by the hooks, follow the original rules from the plugin:

- **URGENT FAST checkpoint** — if the reminder is marked **URGENT**, the user's message is a correction, interruption signal, or negative feedback. Capture it as `UPDATE_MEMORY` (`feedback_interruptions.md` or `feedback_wtf.md`) via `niblet-apply` **before** answering them. Then continue with their request.
- **FAST checkpoint** — turn-local findings. Write `ADD_KB_ENTRY` or `UPDATE_MEMORY` via `niblet-apply`. Never create skills/commands here. Delete the `PENDING_FAST` marker when done.
- **DEEP checkpoint** — previous session analysis. Spawn `niblet-deep` sub-agent, route actions through `niblet-apply`, delete the queue entry.
- **DISTILL checkpoint** — KB consolidation. Spawn `niblet-distill` sub-agent.
- **AUDIT checkpoint** — periodic health check. Spawn `niblet-audit` sub-agent.

All checkpoints are **background bookkeeping** — non-blocking, silent. Handle the user's request first, unless the FAST reminder is URGENT; in that case capture the feedback first.

---

## Universal rules (both runtimes)

### Capture interruptions and negative feedback immediately

If the user **stops execution** (Ctrl+C, TaskStop), **rejects a plan** (ExitPlanMode reject/revise), or **sends a correction** after an interruption, capture it as memory feedback **before doing anything else**:

```json
{
  "project_root": "/abs/path/to/project",
  "action": {
    "action": "UPDATE_MEMORY",
    "scope": "project",
    "file": "feedback_interruptions.md",
    "content": "---\nname: feedback-interruptions\ndescription: User corrections after interrupted execution\nmetadata: { type: interruption, source: <session_id> }\n---\n\n- <timestamp>: User stopped execution because… <exact correction>\n- <timestamp>: Should have done: <what user wants instead>\n"
  }
}
```

**Do not paraphrase.** Use the user's exact words for the correction. This is critical input for future sessions.

Also capture "wtf" and negative sentiment immediately. If the user's message contains **any** of these signals (case-insensitive):

- `wtf`
- `не так`
- `переделай`
- `стоп`
- `заново`
- `это бред`
- `ничего не работает`
- `никогда так не делай`
- `never do that`

Capture it as negative feedback by calling `niblet_apply` with these arguments:

```json
{
  "project_root": "/abs/path/to/project",
  "action": {
    "action": "UPDATE_MEMORY",
    "scope": "project",
    "file": "feedback_wtf.md",
    "content": "---\nname: feedback-wtf\ndescription: Negative sentiment triggers to avoid\nmetadata: { type: negative_feedback, source: <session_id> }\n---\n\n- <timestamp>: Message: \"<exact user message>\"\n- <timestamp>: Context: <what you did that triggered it>\n- <timestamp>: Fix: <what should be done differently next time>\n"
  }
}
```

Then **continue** with the user's actual request. Do not apologize at length — just fix it and move on.

For **Claude Code**: when the `NIBLET CHECKPOINT (fast)` reminder includes an **URGENT** note, treat the user's message as a correction/negative feedback and apply `UPDATE_MEMORY` before continuing with their request.

For **Kimi Code CLI**: there are no automatic hooks, so you must call the niblet tools yourself following the rules above.

### Single write entry point — `niblet_apply` / `niblet-apply`

Never call `Edit`/`Write` directly to KB, memory, skills, commands, scripts, or `AGENTS.md`/`CLAUDE.md`. Always route through the secure helper.

**For Kimi Code CLI**: call the `niblet_apply` MCP tool with arguments containing `project_root` and `action`.

**For Claude**: stage the JSON to a file with `Write`, then pipe via Bash:
```bash
niblet-apply --project-root "$PROJECT_ROOT" < <project>/.niblet/inbox/<random>.json
```

Never `echo '<json>' | niblet-apply` — shell metachars in content can break out before validation.

### What NOT to save

- Code patterns derivable by reading the source.
- Step-by-step tool calls. KB records *findings*, not your action log.
- Apologies, hedges, "I'll do better."
- Project state in flux (current branch, in-progress work, today's TODOs).
- Anything that might be a secret.

### Output format hints

**KB entry** (`kb/<topic>.md`):
```markdown
# <Topic>

<One paragraph: what this is and why it matters.>

## Key facts
- Fact 1 — file path or symbol if applicable
- Fact 2 — …

## Why this works this way
<If non-obvious. Otherwise omit.>

## Gotchas
- Pitfall 1 — and how to avoid it.
```

**Memory feedback** (`memory/feedback_<slug>.md`):
```markdown
---
name: feedback-<slug>
description: <one-line summary>
metadata: { type: feedback }
---

<The rule itself.>

**Why:** <the reason the user gave>
**How to apply:** <when this kicks in>
```

**Skill proposal** (`.niblet/proposals/<ts>-<slug>.md`):
```markdown
---
action: CREATE_SKILL
scope: project
target: <project>/skills/niblet/<name>/SKILL.md
created: <UTC timestamp>
---

---
name: <name>
description: <when to use this skill>
---

# <Title>

## When to use
…

## Steps
1. …
```

## Configuration reference

| Variable | Default | Purpose |
|---|---|---|
| `NIBLET_DEEP_THRESHOLD` | `20` | Safety-net: enqueue DEEP mid-session after this many turns (Claude only) |
| `NIBLET_KB_DISTILL_COUNT` | `20` | KB file count above which DISTILL is queued |
| `NIBLET_KB_DISTILL_BYTES` | `200000` | KB byte total above which DISTILL is queued |
| `NIBLET_AUDIT_INTERVAL_SESSIONS` | `5` | Sessions between AUDIT triggers |
| `NIBLET_GUARDED_APPLY` | unset | When `1`, auto-promotes `risk=low + confidence=high` MERGE/UPDATE_KB_ENTRY |
| `NIBLET_BEGINNER_UX` | unset | When `1`, embeds `beginner_summary` in proposals; plain-language status |
