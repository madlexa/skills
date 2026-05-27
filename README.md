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
auto-writes findings to the project knowledge base. At session end, a
sub-agent extracts reusable workflow patterns and lands them as proposals
you review before promoting.

**Two layers, two trust tiers:**
- **FAST** (every turn) — agent writes findings to `.claude/kb/` and memory
  feedback. Auto-write, local, reversible.
- **DEEP** (SessionEnd) — sub-agent extracts workflow patterns; everything
  that could affect future sessions (skills, commands, CLAUDE.md edits, any
  global write) is staged as a proposal in `.niblet/proposals/`. You promote
  via `mv`.

**Sanitized capture** — observe.sh logs only tool name + safe path + exit
code. `tool_input` and `tool_response` content (where secrets and untrusted
text live) is never stored. Closes the persistent prompt-injection vector.

**Per-session isolation** — markers and counters scoped to
`<project>/.niblet/sessions/<session-id>/`. Parallel sessions never share state.

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

## Local development

To work on a plugin without publishing:

```bash
claude --plugin-dir ./plugins/niblet
```
