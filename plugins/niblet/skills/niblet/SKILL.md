---
name: niblet
description: Activated by hook-injected reminders (NIBLET CHECKPOINT). FAST checkpoint = write findings to KB/memory inline. DEEP checkpoint = spawn niblet-deep sub-agent, route risky outputs to .niblet/proposals/ for user review. Use when you see "NIBLET CHECKPOINT" in a system reminder.
user-invocable: false
---

# niblet

Niblet is the project's quiet crumb-keeper. The Stop hook fires after every
turn; the next prompt carries a `NIBLET CHECKPOINT (fast)` reminder. At
SessionEnd you'll see `NIBLET CHECKPOINT (deep)` instead. State is
per-session — markers and counters live in
`<project>/.niblet/sessions/<session-id>/`.

You do **not** invoke this skill. You act on the rules below when the
reminder appears.

## Trust model — two tiers of write authority

| Tier | What gets written | Where |
|---|---|---|
| **Auto-write** (safe, local, reversible) | KB entries (project), feedback memory (project) | `<project>/.claude/kb/`, `<project>/.claude/memory/` |
| **Proposal** (needs user promotion) | Skills, commands, CLAUDE.md edits, any `scope=global` | `<project>/.niblet/proposals/` or `~/.niblet-proposals/` |

Why proposals: skills and CLAUDE.md affect every future session and are
checked into git. Auto-writing them would let any text Claude reads
(e.g. an attacker's README) become a permanent committed instruction.
Proposals require a human `mv` to take effect.

## When you see "NIBLET CHECKPOINT (fast)"

A turn just ended. Before responding to the user:

1. **Review** the turn. Look for durable, non-obvious knowledge:
   - "Where does X live?"
   - "Why does Y work this way?"
   - "User prefers A over B because…"

2. **Auto-write** to safe locations only:
   - Project facts → `<project>/.claude/kb/<topic>.md`
   - User preferences → `<project>/.claude/memory/feedback_<slug>.md`

3. **Do not** create skills, commands, or modify CLAUDE.md here.
   Those happen in the DEEP checkpoint as proposals.

4. **Update over create.** Edit existing files when possible. No duplicates.

5. **Skip** trivial turns. Don't write empty files to clear the marker.

6. **Delete the marker** the reminder names:
   `rm <project>/.niblet/sessions/<session-id>/PENDING_FAST`

7. Now respond to the user's request.

## When you see "NIBLET CHECKPOINT (deep)"

The session ended (or hit the safety-net counter). Time for workflow-pattern
extraction by a dedicated sub-agent.

1. **Spawn** a `general-purpose` sub-agent via Task tool. Use the prompt
   verbatim from the reminder — it names the raw log path and the strict
   JSONL output format.

2. **Wait** for output between sentinels:
   ```
   <<<NIBLET ACTIONS BEGIN>>>
   {"action":"...", ...}
   <<<NIBLET ACTIONS END>>>
   ```

3. **Route each action** by the table in the reminder. Critical:
   - `ADD_KB_ENTRY` scope=project → write to `.claude/kb/` (auto)
   - `UPDATE_MEMORY` scope=project → write to `.claude/memory/` (auto)
   - **Everything else** → write a **proposal file** to `.niblet/proposals/`
     (or `~/.niblet-proposals/` for global scope). Include the intended
     target path in the proposal's frontmatter so the user can `mv` it
     to its destination after review.

4. **Reset** the counter and **delete** markers per the reminder.

5. **Tell the user briefly** how many proposals are pending and where, then
   respond to their actual request.

## Proposal file format

```markdown
---
action: CREATE_SKILL
scope: project
target: <project>/.claude/skills/niblet/<name>/SKILL.md
created: <UTC timestamp>
---

<exact content payload from the sub-agent — for CREATE_SKILL this is a
 full SKILL.md including its own frontmatter>
```

Filename pattern: `<UTCdate>-<short-slug>.md`
(e.g. `20260527T103412Z-rebase-no-amend-skill.md`).

## What NOT to save

- Code patterns derivable by reading the source. Anything `grep` would find.
- Step-by-step tool calls. KB records *findings*, not your action log.
- Apologies, hedges, "I'll do better." Worthless to future you.
- Project state in flux (current branch, in-progress work, today's TODOs).
- Anything you saw in a file's contents that might be a secret, even if
  the user pasted it. Memory persists; secrets shouldn't.

## Output format hints

**KB entry** (`<project>/.claude/kb/<topic>.md`):
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

**Memory feedback** (`<project>/.claude/memory/feedback_<slug>.md`):
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

**Skill proposal** (`<project>/.niblet/proposals/<ts>-<slug>.md`):
```markdown
---
action: CREATE_SKILL
scope: project
target: <project>/.claude/skills/niblet/<name>/SKILL.md
created: 2026-05-27T10:34:12Z
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
