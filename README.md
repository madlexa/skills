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

### niblet

The diligent crumb-keeper for AI coding sessions. After every subtask, Niblet
quietly notes what was discovered — findings about the codebase, workflows
that worked, gotchas, user preferences — and writes them to the right place
(KB entry, workflow skill, command, or memory file). Next session, all of it
is already there.

**Hybrid design:**
- **FAST layer** — main agent jots findings inline after each subtask
- **DEEP layer** — sub-agent extracts reusable workflow patterns at session end

**Per-project** storage, auto-`.gitignore` of raw logs, `.claude/kb/` and
`.claude/skills/niblet/` committed to git so the whole team benefits.

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
