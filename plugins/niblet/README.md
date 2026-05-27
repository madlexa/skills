# niblet

The diligent crumb-keeper for AI coding sessions in Claude Code (and Kimi Code).

Every session produces discoveries, workflow patterns, and project-specific
knowledge. Niblet quietly captures them — no manual `/save` or `/evolve`
commands. After every subtask it jots findings; at session end a sub-agent
extracts reusable workflow patterns into skills. The next session starts
with all of it already loaded.

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
knowledge belongs as a KB entry, a workflow skill, a CLAUDE.md addition, or
a memory file — and writes it to the right place.

## How it works

```
Session
  │
  ├── Observer (hook)            PreToolUse / PostToolUse → JSONL log
  │                              Auto-creates .niblet/ + .gitignore
  │
  ├── FAST layer (main agent)    SubagentStop → PENDING_FAST marker
  │                              UserPromptSubmit → reminder injection
  │                              Agent writes findings to .claude/kb/
  │
  └── DEEP layer (sub-agent)     Stop or counter ≥ 5 → PENDING_DEEP marker
                                 Agent spawns sub-agent via Task tool
                                 Sub-agent extracts workflow patterns → skills
```

## Storage

| Location | Contents | Git |
|---|---|---|
| `<project>/.claude/kb/` | Project knowledge base (findings) | yes |
| `<project>/.claude/skills/niblet/` | Project workflow skills | yes |
| `<project>/.claude/commands/niblet/` | Project slash commands | yes |
| `<project>/.claude/memory/` | Project memory files | yes |
| `<project>/.niblet/` | Raw logs, markers, counters | **gitignored** (auto) |
| `~/.claude/skills/niblet/` | Cross-project skills | host home |
| `~/.claude/memory/` | Cross-project memory | host home |

## Configuration

Environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `NIBLET_DEEP_THRESHOLD` | `5` | Subtasks before DEEP layer fires |

## Uninstall

```
/plugin uninstall niblet@madlexa-skills
```

Project-local `.niblet/`, `.claude/kb/`, etc. are **not** removed — they
are project data, not plugin runtime.

## Files

```
niblet/
├── .claude-plugin/plugin.json     # plugin manifest
├── skills/niblet/SKILL.md         # how agent reacts to checkpoints
├── agents/niblet-deep.md          # sub-agent prompt for DEEP layer
├── hooks/
│   ├── hooks.json                 # hook registration (Claude Code reads this)
│   ├── observe.sh                 # PreToolUse/PostToolUse logger
│   ├── on_subagent_stop.sh        # touch PENDING_FAST
│   ├── on_stop.sh                 # touch PENDING_DEEP
│   └── on_prompt_submit.sh        # inject FAST/DEEP reminder
├── lib/                           # paths.sh, gitignore.sh, jsonl.sh
└── tests/smoke_test.sh            # end-to-end manual test
```

## Status

Initial release (0.1.0). End-to-end smoke test passes. Live behavior on
real sessions will be validated in upcoming iterations.
