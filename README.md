# madlexa/skills

Plugin marketplace for [Claude Code](https://code.claude.com) and compatible
agents (Kimi Code via shared `SKILL.md` / hooks format).

## Install

Add this marketplace once:

```
/plugin marketplace add madlexa/skills
```

Then install any plugin from it:

```
/plugin install niblet@madlexa-skills
```

To update later:

```
/plugin marketplace update madlexa-skills
```

## Plugins

### niblet (v0.2.0)

The diligent crumb-keeper for AI coding sessions. After every turn, Niblet
auto-writes findings to the project knowledge base via a single secure
helper. At session end, a sub-agent extracts reusable workflow patterns and
lands them as proposals you review before promoting (via the action-aware
`niblet-promote` helper — never a raw `mv`).

**Two layers, two trust tiers:**
- **FAST** (every turn) — agent writes findings to `.claude/kb/` and memory
  feedback. Auto-write, local, reversible.
- **DEEP** (SessionEnd) — sub-agent extracts workflow patterns; everything
  that could affect future sessions (skills, commands, CLAUDE.md edits, any
  global write) is staged as a proposal in `.niblet/proposals/`. You promote
  via the `niblet-promote` helper — it strips the proposal envelope,
  appends `UPDATE_CLAUDE` additions under the named section instead of
  overwriting, and containment-checks the target.

**Sanitized capture** — observe.sh logs only tool name + safe path + exit
code. `tool_input` and `tool_response` content (where secrets and untrusted
text live) is never stored. Closes the persistent prompt-injection vector.

**Validated writes** — every ACTION the agent applies goes through
`bin/niblet-apply`, which enforces slug rules and canonical path
containment. Sub-agent-supplied filenames cannot escape their allowed dir.

**Cross-session DEEP queue** — `SessionEnd` writes a queue entry that any
subsequent session drains, even with a new session id. No orphan markers.

**Honest KB surfacing** — a SessionStart hook emits a compact KB index
reminder so the agent knows which `.claude/kb/` topics exist.

See [plugins/niblet/README.md](plugins/niblet/README.md).

## Structure

```
skills/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/
    └── <plugin-name>/
        ├── .claude-plugin/plugin.json
        ├── README.md
        ├── skills/
        ├── agents/
        ├── hooks/
        └── ...
```

## Platform support

Plugins in this marketplace ship as POSIX shell scripts. They run natively
on **macOS** and **Linux**. Windows users need **WSL2** (recommended) or
**Git Bash** — `cmd.exe` and PowerShell are not supported. See each
plugin's README for its specific dependencies (typically `bash`, `jq`,
`python3`, and `git`).

## Local development

To work on a plugin without publishing:

```bash
claude --plugin-dir ./plugins/niblet
```
