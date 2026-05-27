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
Proposals require a human action to take effect.

### Single write entry point — `bin/niblet-apply`

You do NOT call Edit/Write directly when acting on a NIBLET CHECKPOINT.
Every action goes through the plugin's secure helper, which validates
slugs, enforces path containment, and routes to auto-write vs proposal:

```bash
echo '{"action":"ADD_KB_ENTRY","scope":"project","topic":"auth.md","content":"…"}' \
  | "${CLAUDE_PLUGIN_ROOT}/bin/niblet-apply" --project-root "$PROJECT_ROOT"
```

The reminder text spells out the exact command per action. Direct Edit/Write
bypasses validation and is a security regression — don't do it.

## When you see "NIBLET CHECKPOINT (fast)"

A turn just ended. Before responding to the user:

1. **Review** the turn. Look for durable, non-obvious knowledge:
   - "Where does X live?"
   - "Why does Y work this way?"
   - "User prefers A over B because…"

2. **Pipe an ACTION through `niblet-apply`** — never Edit/Write directly:
   - Project facts → `ADD_KB_ENTRY` action with `topic` (slug, ending `.md`)
   - User preferences → `UPDATE_MEMORY` action with `file=feedback_<slug>.md`

3. **Do not** create skills, commands, or modify CLAUDE.md here.
   Those happen in the DEEP checkpoint as proposals.

4. **Update over create.** Reuse an existing slug to land in the same file.
   The helper happily writes over an existing file; no duplicates needed.

5. **Skip** trivial turns. Don't fire ACTIONs to clear the marker.

6. **Delete the marker** the reminder names:
   `rm <project>/.niblet/sessions/<session-id>/PENDING_FAST`

7. Now respond to the user's request.

## When you see "NIBLET CHECKPOINT (deep)"

A previous session has ended. Its raw log is queued for analysis.

1. **Spawn** a `general-purpose` sub-agent via Task tool. Use the prompt
   verbatim from the reminder — it names the **queued raw log** (not the
   current session's), the slug constraints, and the strict JSONL format.

2. **Wait** for output between sentinels:
   ```
   <<<NIBLET ACTIONS BEGIN>>>
   {"action":"...", ...}
   <<<NIBLET ACTIONS END>>>
   ```

3. **Pipe each ACTION line** through `niblet-apply` — the helper enforces
   slug rules, containment, and the auto vs proposal routing. You don't
   route yourself; the helper does. Watch its stdout:
   ```
   applied: ADD_KB_ENTRY -> /…/.claude/kb/auth.md
   proposal: CREATE_SKILL -> /…/.niblet/proposals/<ts>-<slug>.md
   ```
   Anything rejected (bad slug, path escape) lands as a proposal with a
   `rejected_reason` so the user can see what the sub-agent tried.

4. **Delete the queue entry** the reminder names:
   `rm <project>/.niblet/pending_deep/<ts>-<session>.queue`

5. **Tell the user briefly** what was applied vs proposed, including
   `<project>/.niblet/proposals/` so they can review with
   `bin/niblet-promote` — never raw `mv`. Then respond to their request.

## Proposal promotion — `bin/niblet-promote`

When the user has reviewed a proposal and wants to apply it, the canonical
command is:

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/niblet-promote" <proposal-file>
```

The helper is action-aware:
- `CREATE_SKILL` / `CREATE_COMMAND` / `ADD_KB_ENTRY` / `UPDATE_MEMORY` →
  strips the envelope, writes the payload to the target path.
- `UPDATE_CLAUDE` → locates the named `## section` heading in the target
  CLAUDE.md and **appends** the addition under it. Creates the section
  if absent. Never overwrites the file.

Plain `mv` would double-wrap SKILL frontmatter and replace CLAUDE.md
wholesale — do not document `mv` as a promotion path.

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

Filename pattern: `<UTCdate>-<ACTION>-<short-slug>.md`
(e.g. `20260527T103412Z-CREATE_SKILL-rebase-no-amend.md`).

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
