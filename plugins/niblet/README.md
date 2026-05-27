# niblet

The diligent crumb-keeper for AI coding sessions in Claude Code (and Kimi Code).

Every session produces discoveries, workflow patterns, and project-specific
knowledge. Niblet quietly captures them — no manual `/save` or `/evolve`
commands. After every turn it auto-writes findings to the project KB. At
session end a sub-agent extracts reusable workflow patterns and lands them
as **proposals** you review before promoting. The next session starts with
everything already loaded.

## Install

```
/plugin marketplace add madlexa/skills
/plugin install niblet@madlexa-skills
```

Or for local development:

```bash
claude --plugin-dir /path/to/madlexa/skills/plugins/niblet
```

## Why it exists

Existing tools observe but don't act:
- `continuous-learning-v2` (6.3K installs) — captures patterns with confidence
  scoring, but you still have to run `/evolve` to create skills.
- `claude-mem` — stores raw context, no decision-making about *where*
  knowledge belongs.

Niblet adds the missing layer: **judgement**. It decides whether new
knowledge belongs as a KB entry (auto), a workflow skill (proposal), a
CLAUDE.md addition (proposal), or a memory file (auto) — and routes it
accordingly.

## How it works

```
Session
  │
  ├── Observer (PreToolUse / PostToolUse hooks)
  │     observe.sh — SANITIZED capture: tool name + safe path + exit code
  │     Never logs tool_input/tool_response content (secret-safe)
  │     Initializes .niblet/ + .gitignore on first call (idempotent)
  │
  ├── Stop hook (after every turn)
  │     on_stop.sh:
  │       touch sessions/<id>/PENDING_FAST
  │       counter++
  │       counter ≥ NIBLET_DEEP_THRESHOLD (default 20) → touch PENDING_DEEP
  │         [safety net only — marathon sessions]
  │
  ├── SessionEnd hook (session terminates)
  │     on_session_end.sh:
  │       touch sessions/<id>/PENDING_DEEP unconditionally
  │       [the natural moment for workflow extraction]
  │
  ├── FAST checkpoint (agent acts inline)
  │     UserPromptSubmit hook → reminder for THIS session's PENDING_FAST
  │     Agent writes findings to .claude/kb/ and feedback memory
  │     [AUTO-WRITE tier — safe, local, reversible]
  │
  └── DEEP checkpoint (sub-agent extracts, parent routes to proposals)
        UserPromptSubmit hook → reminder for THIS session's PENDING_DEEP
        Agent spawns niblet-deep via Task tool
        Sub-agent emits JSONL ACTIONs between sentinels
        Agent routes each: KB/memory project → auto; everything else → proposal
        Reports proposal count to user; user promotes via `mv`
```

**Per-session isolation.** Markers and counters live in
`<project>/.niblet/sessions/<session-id>/`. Parallel sessions never share
checkpoint state.

## Trust model

Two tiers — what the plugin will and won't auto-write:

| Action | Scope | Behavior |
|---|---|---|
| `ADD_KB_ENTRY` | project | **auto** → `<project>/.claude/kb/<topic>.md` |
| `UPDATE_MEMORY` | project | **auto** → `<project>/.claude/memory/feedback_<slug>.md` |
| `CREATE_SKILL` | any | **proposal** → `.niblet/proposals/<ts>-<slug>.md` |
| `CREATE_COMMAND` | any | **proposal** |
| `UPDATE_CLAUDE` | project | **proposal** |
| `ADD_KB_ENTRY` | global | **proposal** → `~/.niblet-proposals/` |
| `UPDATE_MEMORY` | global | **proposal** |

Skills, commands, and CLAUDE.md affect every future session and live in
git. Auto-writing them would let any text Claude reads (an attacker's
README, a malicious .env contents, etc.) become a permanent committed
instruction. Proposals require a human `mv` to take effect.

## Storage

| Location | Contents | Git |
|---|---|---|
| `<project>/.claude/kb/` | Project KB (findings) — auto-written | yes |
| `<project>/.claude/memory/` | Project memory feedback — auto-written | yes |
| `<project>/.claude/skills/niblet/` | Project skills — manually promoted from proposals | yes |
| `<project>/.claude/commands/niblet/` | Project commands — manually promoted | yes |
| `<project>/.niblet/proposals/` | Pending project proposals waiting for `mv` | gitignored |
| `<project>/.niblet/raw/` | Per-session sanitized JSONL log | gitignored |
| `<project>/.niblet/sessions/<id>/` | Per-session markers + counter | gitignored |
| `~/.claude/skills/niblet/`, `~/.claude/memory/` | Cross-project artifacts | host home |
| `~/.niblet-proposals/` | Pending global proposals | host home |

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `NIBLET_DEEP_THRESHOLD` | `20` | Safety-net: turns per session before DEEP fires *mid-session*. Normal DEEP fires on SessionEnd regardless. |

## Uninstall

```
/plugin uninstall niblet@madlexa-skills
```

Project-local `.niblet/`, `.claude/kb/`, and any pending proposals are
**not** removed — they are user data, not plugin runtime.

## Files

```
niblet/
├── .claude-plugin/plugin.json     # plugin manifest (0.2.0)
├── skills/niblet/SKILL.md         # how agent reacts to checkpoints
├── agents/niblet-deep.md          # sub-agent for DEEP layer
├── hooks/
│   ├── hooks.json                 # hook registration
│   ├── observe.sh                 # PreToolUse/PostToolUse — sanitized logger
│   ├── on_stop.sh                 # touch PENDING_FAST + counter + safety net
│   ├── on_session_end.sh          # touch PENDING_DEEP at session end
│   └── on_prompt_submit.sh        # inject per-session FAST/DEEP reminder
├── lib/
│   ├── paths.sh                   # runtime + project root + artifact dirs
│   ├── gitignore.sh               # idempotent .gitignore add
│   ├── jsonl.sh                   # JSONL helpers
│   ├── sanitize.sh                # safe path extraction (no content)
│   └── store.sh                   # single entry: ensure store + gitignore
└── tests/smoke_test.sh            # 31-check contract test suite
```

## Status

**v0.2.0** — addresses two P0 issues from external security review:

- **P0 #1 (lifecycle):** DEEP no longer fires every 5 turns mid-session.
  Moved to SessionEnd. `NIBLET_DEEP_THRESHOLD` becomes safety-net only
  (default 20) for marathon sessions where SessionEnd never fires.
- **P0 #2 (security):** `observe.sh` no longer captures `tool_input` /
  `tool_response` content. Only tool name + project-relative path +
  exit code go to the log. Skills, commands, CLAUDE.md edits, and any
  global writes are routed to `.niblet/proposals/` requiring manual
  `mv` to promote. Closes the persistent prompt-injection vector.

31 contract-level smoke tests pass, including new security regression
checks (verify no secrets leak from tool_input/tool_response to logs).
