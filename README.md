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

### niblet (v0.3.0)

The diligent crumb-keeper for AI coding sessions. After every turn, Niblet
auto-writes findings to the project knowledge base via a single secure
helper. At session end, a sub-agent extracts reusable workflow patterns and
lands them as proposals you review before promoting (via the action-aware
`niblet-promote` helper — never a raw `mv`).

**Five checkpoint layers:**
- **FAST** (every turn) — agent writes findings to `.claude/kb/` and memory
  feedback. Auto-write, local, reversible.
- **DEEP** (SessionEnd) — sub-agent extracts workflow patterns; skills,
  agents, commands, CLAUDE.md edits, and global writes are staged as
  proposals in `.niblet/proposals/`. Promote via `niblet-promote`.
- **DISTILL** (when KB > 20 files or 200 KB) — sub-agent consolidates
  overlapping KB entries to keep the knowledge base dense and non-redundant.
- **AUDIT** (every 5 sessions) — sub-agent scans the artifact index for
  stale paths and contradictions between KB entries.
- **`niblet-status`** — dashboard showing KB counts, pending proposals,
  promoted artifacts, and queue depths.

**Opt-in guarded auto-apply** — set `NIBLET_GUARDED_APPLY=1` and run
`niblet-promote --guarded-sweep` to auto-promote `risk=low + confidence=high`
`MERGE_KB_ENTRY` / `UPDATE_KB_ENTRY` proposals. A timestamped backup is
written before each overwrite. All other action types remain manual.

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
