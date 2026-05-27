---
name: niblet
description: Activated by hook-injected reminders (NIBLET CHECKPOINT). Reacts to FAST checkpoint (write findings inline) and DEEP checkpoint (spawn sub-agent for pattern extraction). Use when you see "NIBLET CHECKPOINT" in a system reminder.
user-invocable: false
---

# niblet

Niblet is the project's quiet crumb-keeper. It rides along inside the session,
captures every discovery worth keeping, and writes it where it'll be useful
next time.

This skill defines how you (the agent) respond to Niblet's checkpoint
reminders, which the plugin's hooks inject into the system context. You do
not invoke this skill — you act on its rules when a `NIBLET CHECKPOINT`
reminder appears.

## When you see "NIBLET CHECKPOINT (fast)"

A subtask just completed. Before responding to the user's current message:

1. **Review** the previous turns. Identify durable, non-obvious knowledge.
   - "Where does X live in this codebase?"
   - "Why does Y work this way?" / "Why did we reject approach Z?"
   - "User prefers A over B because…"

2. **Write** to the project (paths are spelled out in the reminder text):
   - Project facts → `<project>/.claude/kb/<topic>.md` — one file per topic
   - User preferences / corrections → `<project>/.claude/memory/feedback_<slug>.md`

3. **Update over create.** If a relevant file already exists, edit it.
   Never duplicate a concept across files.

4. **Skip** if the turns were trivial — only tool calls without real
   discovery. Do not write empty files just to satisfy the checkpoint.

5. **Delete the marker:** `rm <project>/.niblet/PENDING_FAST`.

6. Now respond to the user's actual request.

## When you see "NIBLET CHECKPOINT (deep)"

The session has produced ≥ N subtasks (or just ended). Pattern extraction
deserves a dedicated agent, not your active working context.

1. **Spawn** a `general-purpose` sub-agent using the Task tool. Use the prompt
   embedded in the reminder verbatim — it tells the sub-agent exactly which
   files to read and which ACTION lines to emit.

2. **Wait** for the sub-agent to return its list of ACTION lines.

3. **Apply** each ACTION by writing the file at the correct path. The reminder
   spells out the mapping (`CREATE_SKILL scope=project` → project skills dir,
   `scope=global` → host home, etc.). For `CREATE_SKILL` / `CREATE_COMMAND`,
   include valid SKILL.md frontmatter.

4. **Reset** counters and **delete** markers:
   ```
   rm <project>/.niblet/PENDING_DEEP
   rm -f <project>/.niblet/PENDING_FAST
   printf 0 > <project>/.niblet/task_counter
   ```

5. Now respond to the user's actual request.

## What NOT to save

- Code patterns derivable by reading the source. Anything `grep` would find.
- Step-by-step actions you took. The KB records *findings*, not your tool log.
- Apologies, hedges, "I'll be more careful next time." Worthless to future you.
- Project state in flux (current branch, work in progress, today's TODOs).

## Output format hints

**KB entry** (`<project>/.claude/kb/<topic>.md`):
```markdown
# <Topic>

<One-paragraph summary of what this is and why it matters.>

## Key facts
- Fact 1 — with file path or symbol if applicable.
- Fact 2 — …

## Why this works this way
<If the design has non-obvious reasoning, state it. Otherwise omit.>

## Gotchas
- Pitfall 1 — and how to avoid it.
```

**Skill** (`<project>/.claude/skills/niblet/<name>/SKILL.md`):
```markdown
---
name: <kebab-name>
description: <when to use this skill — be specific so future-you recognises the trigger>
---

# <Title>

## When to use
<Concrete trigger conditions.>

## Steps
1. …
2. …

## Why this works
<Optional: the insight that makes the pattern correct.>
```

**Memory** (`<project>/.claude/memory/feedback_<slug>.md`):
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
