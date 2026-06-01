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
| **Proposal** (needs user promotion) | Skills, agents, scripts, commands, CLAUDE.md edits, any `scope=global` | `<project>/.niblet/proposals/` or `~/.niblet-proposals/` |

### Action types and their routing

| Action | Scope | Routing |
|---|---|---|
| `ADD_KB_ENTRY` | project | **auto-write** → `<project>/.claude/kb/<topic>.md` |
| `MERGE_KB_ENTRY` | project | **auto-write** → merged into `<project>/.claude/kb/<topic>.md` |
| `UPDATE_KB_ENTRY` | project | **auto-write** → overwrites `<project>/.claude/kb/<topic>.md` |
| `DEPRECATE_KB_ENTRY` | project | **auto-write** → prepends deprecation notice (tombstone if absent) |
| `UPDATE_MEMORY` | project | **auto-write** → `<project>/.claude/memory/feedback_<slug>.md` |
| `CREATE_SKILL` | any | **proposal** |
| `CREATE_AGENT` | any | **proposal** |
| `CREATE_SCRIPT` | any | **proposal** (envelope includes bash/python validation result) |
| `CREATE_COMMAND` | any | **proposal** |
| `UPDATE_SKILL` | any | **proposal** (backup written before overwrite on promotion) |
| `UPDATE_AGENT` | any | **proposal** (backup written before overwrite on promotion) |
| `UPDATE_COMMAND` | any | **proposal** (backup written before overwrite on promotion) |
| `UPDATE_SCRIPT` | any | **proposal** (backup written before overwrite on promotion) |
| `UPDATE_CLAUDE` | project | **proposal** |
| `OPEN_QUESTION` | any | **proposal** (question text for human review) |
| `AUDIT_REPORT` | any | **proposal** (structured audit findings for human review) |
| `ADD_KB_ENTRY` | global | **proposal** → `~/.niblet-proposals/` |
| `UPDATE_MEMORY` | global | **proposal** |
| unknown action | any | **proposal** with `rejected_reason=unknown-action` |
| bad slug or path escape | any | **proposal** with `rejected_reason` |

Why proposals: skills and CLAUDE.md affect every future session and are
checked into git. Auto-writing them would let any text Claude reads
(e.g. an attacker's README) become a permanent committed instruction.
Proposals require a human action to take effect.

### Single write entry point — `bin/niblet-apply`

You do NOT call Edit/Write directly to KB/memory/skills/commands/CLAUDE.md
when acting on a NIBLET CHECKPOINT. Every action goes through the plugin's
secure helper, which validates slugs, enforces path containment, and
routes to auto-write vs proposal.

**Always Write-then-stdin. Never echo-pipe.** The `content` / `addition`
fields can legitimately contain single quotes, backslashes, and other
shell metachars (it's free-form markdown). An `echo '<json>' | …`
invocation would let those bytes break out of the quoting before
niblet-apply ever validates anything. The Write tool does not
shell-interpret content, so the staged file is byte-exact:

```bash
# Step 1 (Write tool, NOT bash): create the JSON file
Write file_path=<project>/.niblet/inbox/<random>.json
Content:
  {"action":"ADD_KB_ENTRY","scope":"project","topic":"auth.md","content":"…"}

# Step 2 (Bash tool): feed via stdin redirection. `niblet-apply` resolves
# on PATH — Claude Code adds the plugin's bin/ to the hook/Bash PATH, so
# the bare command works without `${CLAUDE_PLUGIN_ROOT}` expansion.
niblet-apply --project-root "$PROJECT_ROOT" \
  < <project>/.niblet/inbox/<random>.json
```

The reminder text spells out the exact command per action. Direct Edit/Write
to the target tree bypasses validation and is a security regression —
don't do it. `echo '<json>' | niblet-apply` is also a security regression
— don't do it either.

## Checkpoints are background bookkeeping — non-blocking and silent

All four checkpoints follow the same rules, no matter what the reminder says:

- **User first.** Fully handle the user's request before processing a checkpoint.
  If you're mid-task, or unsure it's worth it, just delete the marker/queue entry
  and skip — a future session won't re-create it for a trivial session.
- **Stay quiet.** Never paste raw JSON action bodies into your reply, and never
  narrate the bookkeeping. Mention something in one short line *only* if an action
  was actually applied or proposed.
- **NOTHING = silence.** If the analysis yields only `NOTHING`, silently delete the
  queue entry. Do not write a `NOTHING` file and do not tell the user.

## When you see "NIBLET CHECKPOINT (fast)"

A turn just ended. After you've handled the user (or right away if there's
nothing to answer), quietly:

1. **Review** the turn. Look for durable, non-obvious knowledge:
   - "Where does X live?"
   - "Why does Y work this way?"
   - "User prefers A over B because…"

2. **Stage an ACTION JSON via Write, then pipe it into `niblet-apply`** —
   never Edit/Write the target file directly, never `echo '<json>' | …`:
   - Project facts → `ADD_KB_ENTRY` action with `topic` (slug, ending `.md`)
   - User preferences → `UPDATE_MEMORY` action with `file=feedback_<slug>.md`

3. **Do not** create skills, commands, or modify CLAUDE.md here.
   Those happen in the DEEP checkpoint as proposals.

4. **Update over create.** Reuse an existing slug to land in the same file.
   The helper happily writes over an existing file; no duplicates needed.

5. **Skip** trivial turns. Don't fire ACTIONs to clear the marker.

6. **Delete the marker** the reminder names:
   `rm <project>/.niblet/sessions/<session-id>/PENDING_FAST`

7. Return to the user's request (or, if you already answered it, you're done —
   don't announce the checkpoint).

## When you see "NIBLET CHECKPOINT (deep)"

A previous session has ended. Its raw log is queued for analysis. Process it
only *after* the user's request (see "background bookkeeping" above). If the
raw log is absent or shows fewer than `NIBLET_DEEP_MIN_TOOLCALLS` (default 8)
tool calls, there's nothing to extract — just `rm` the queue entry and move on.

1. **Spawn** a `general-purpose` sub-agent via Task tool. Use the prompt
   verbatim from the reminder — it names the **queued raw log** (not the
   current session's), the slug constraints, and the strict JSONL format.

2. **Wait** for output between sentinels:
   ```
   <<<NIBLET ACTIONS BEGIN>>>
   {"action":"...", ...}
   <<<NIBLET ACTIONS END>>>
   ```

3. **Stage each ACTION JSON via Write, then pipe via stdin** through
   `niblet-apply` — the helper enforces slug rules, containment, and the
   auto vs proposal routing. You don't route yourself; the helper does.
   Use one inbox file per ACTION (`$STORE/inbox/<random>.json`). Watch
   stdout:
   ```
   applied: ADD_KB_ENTRY -> /…/.claude/kb/auth.md
   proposal: CREATE_SKILL -> /…/.niblet/proposals/<ts>-<slug>.md
   ```
   Anything rejected (bad slug, path escape) lands as a proposal with a
   `rejected_reason` so the user can see what the sub-agent tried.

4. **Delete the queue entry** the reminder names:
   `rm <project>/.niblet/pending_deep/<ts>-<session>.queue`

5. **Only if** something was applied or proposed, mention it in one short line
   with `<project>/.niblet/proposals/` so they can review with `niblet-promote`
   (never raw `mv`). If everything was `NOTHING`, say nothing.

## When you see "NIBLET CHECKPOINT (distill)"

The project KB has grown above the distill threshold (default: 20 files or
200 000 bytes). Process it only after the user's request (background bookkeeping):

1. **Spawn** a `general-purpose` sub-agent via Task tool. Use the prompt
   verbatim from the reminder — it names the **KB directory**, memory
   directory, digests directory, and project root.

2. **Wait** for output between sentinels — same format as DEEP:
   ```
   <<<NIBLET ACTIONS BEGIN>>>
   {"action":"...", ...}
   <<<NIBLET ACTIONS END>>>
   ```

3. **Stage each ACTION JSON via Write, then pipe via stdin** through
   `niblet-apply`:
   - `MERGE_KB_ENTRY`, `UPDATE_KB_ENTRY`, `DEPRECATE_KB_ENTRY` (project scope)
     → **auto-write** (no proposal needed)
   - `CREATE_SKILL`, `CREATE_AGENT`, `CREATE_COMMAND`, any `scope=global`
     → **proposal** (requires user promotion)

4. **Delete the claimed distill entry** the reminder names.

5. **Only if** something was merged, deprecated, or proposed, mention it in one
   short line. If everything was `NOTHING`, say nothing.

## When you see "NIBLET CHECKPOINT (audit)"

A periodic audit is due. The niblet plugin triggers this after every N sessions
(default: 5) by writing an entry to `.niblet/audit_queue/`. Process it only after
the user's request (background bookkeeping):

1. **Spawn** a `general-purpose` sub-agent via Task tool. Use the prompt
   verbatim from the reminder — it names the **artifact index**, KB directory,
   memory directory, digests directory, and project root.

2. **Wait** for output between sentinels — same format as DEEP:
   ```
   <<<NIBLET ACTIONS BEGIN>>>
   {"action":"...", ...}
   <<<NIBLET ACTIONS END>>>
   ```

3. **Stage each ACTION JSON via Write, then pipe via stdin** through
   `niblet-apply`:
   - `UPDATE_KB_ENTRY`, `DEPRECATE_KB_ENTRY` (project scope) → **auto-write**
   - `UPDATE_SKILL`, `UPDATE_AGENT`, `UPDATE_COMMAND` → **proposal**
   - `AUDIT_REPORT`, `OPEN_QUESTION` → **proposal** (for human review)

4. **Delete the claimed audit entry** the reminder names.

5. **Only if** something was updated, deprecated, or proposed, mention it in one
   short line. If everything was `NOTHING`, say nothing.

## Reviewing proposals — `niblet-proposal-reviewer`

Before promoting a proposal, you can invoke the proposal-reviewer agent for
a safety audit. The parent agent (you) spawns it with a prompt listing the
proposals directory and the project root. The sub-agent returns a structured
`approve` / `flag` decision per proposal — it never modifies anything.

```bash
# Optional: review all pending proposals before batch-promoting
# Use niblet-status to see the count first, then spawn niblet-proposal-reviewer
# via the Agent/Task tool with the proposals directory path.
```

The reviewer checks: no secrets in content, one artifact per proposal,
evidence present for UPDATE_*/DEPRECATE_* actions, path containment, no
name conflicts, beginner_summary readable. An `approve` result means safe
to promote; a `flag` result lists the specific checks that failed.

## Configuration reference

| Variable | Default | Purpose |
|---|---|---|
| `NIBLET_DEEP_THRESHOLD` | `20` | Safety-net: enqueue DEEP mid-session after this many turns |
| `NIBLET_KB_DISTILL_COUNT` | `20` | KB file count above which DISTILL is queued (once per session) |
| `NIBLET_KB_DISTILL_BYTES` | `200000` | KB byte total above which DISTILL is queued |
| `NIBLET_AUDIT_INTERVAL_SESSIONS` | `5` | Sessions between AUDIT triggers |
| `NIBLET_GUARDED_APPLY` | unset | When `1`, auto-promotes `risk=low + confidence=high` MERGE/UPDATE_KB_ENTRY without user action |
| `NIBLET_BEGINNER_UX` | unset | When `1`, embeds `beginner_summary` in proposals; niblet-status uses plain language |

## niblet-status

```bash
niblet-status <project_root>
```

Prints a project dashboard without emitting any file content — only counts,
filenames, and paths:

- KB entry count
- Memory file count
- Pending proposals count (with action-type breakdown)
- Promoted artifacts (by category)
- distill_queue and audit_queue depth
- Plain-language "next steps" (non-technical when `NIBLET_BEGINNER_UX=1`)

## Proposal promotion — `niblet-promote`

When the user has reviewed a proposal and wants to apply it, the canonical
command is:

```bash
niblet-promote <proposal-file>
```

The helper is action-aware:
- `CREATE_SKILL` / `CREATE_AGENT` / `CREATE_COMMAND` / `CREATE_SCRIPT` →
  strips the envelope, writes the payload to the target path.
  `CREATE_SCRIPT` re-validates before writing and never sets executable bit.
- `ADD_KB_ENTRY` / `UPDATE_MEMORY` / `MERGE_KB_ENTRY` / `UPDATE_KB_ENTRY` →
  strips the envelope, writes/merges payload to target.
- `UPDATE_SKILL` / `UPDATE_AGENT` / `UPDATE_COMMAND` / `UPDATE_SCRIPT` →
  creates a backup at `<target>.niblet-backup` before overwriting.
- `DEPRECATE_KB_ENTRY` → renames target to `<target>.deprecated`.
- `UPDATE_CLAUDE` → locates the named `## section` heading in the target
  CLAUDE.md and **appends** the addition under it. Creates the section
  if absent. Never overwrites the file.
- `OPEN_QUESTION` / `AUDIT_REPORT` → no-op (already in proposals dir;
  mark as reviewed by removing the file).

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
