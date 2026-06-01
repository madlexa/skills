# madlexa/skills

Plugin marketplace for [Claude Code](https://code.claude.com) and Kimi Code CLI.

This repo contains plugins and skills that extend AI coding agents with
project knowledge, memory, and reusable workflows. Each plugin lives under
`plugins/<name>/` and ships its own README, manifest, and agent instructions.

## Plugins

| Plugin | Description |
|---|---|
| [niblet](#niblet) | Session knowledge keeper — auto-writes KB and memory, queues proposals for skills/agents/CLAUDE.md/AGENTS.md. |
| [speculator](#speculator) | Graph-oriented knowledge base — architecture as entities and edges with a TypeScript CLI and MCP server. |

---

## niblet

Niblet quietly captures discoveries, workflow patterns, and user feedback across
AI coding sessions.

- **Auto-write tier** — KB entries and memory feedback are written directly to
  the project (`.claude/kb/` or `.kimi/kb/`, `.claude/memory/` or `.kimi/memory/`).
- **Proposal tier** — skills, agents, commands, scripts, and `CLAUDE.md`/`AGENTS.md`
  edits are staged as proposals for human review before promotion.
- **Five checkpoints** — FAST (every turn), DEEP (session-end analysis), DISTILL
  (KB consolidation), AUDIT (artifact health), and `niblet-status` dashboard.
- **Sanitized capture** — only tool name + safe path + exit code is logged; raw
  tool content never enters the store.
- **Cross-session DEEP queue** — ended sessions leave work for the next session,
  regardless of session id.

See full details in [plugins/niblet/README.md](plugins/niblet/README.md).

### Install niblet

#### Claude Code

```
/plugin marketplace add madlexa/skills
/plugin install niblet@madlexa-skills
```

Update:

```
/plugin marketplace update madlexa-skills
```

Uninstall:

```
/plugin uninstall niblet@madlexa-skills
```

#### Kimi Code CLI

`kimi-code` installs plugins from a local directory and copies them to a
managed location. Clone the repo first, then install from inside a Kimi session:

```bash
git clone https://github.com/madlexa/skills.git ~/madlexa-skills
```

Inside Kimi Code CLI:

```
/plugins install ~/madlexa-skills/plugins/niblet
/new
```

The plugin provides:

- the `niblet` skill, auto-loaded at session start;
- four MCP tools: `niblet_log`, `niblet_apply`, `niblet_status`, `niblet_promote`.

Because Kimi Code CLI has no hooks, the skill tells the agent to call
`niblet_log` manually after every file mutation.

Update:

```bash
cd ~/madlexa-skills
git pull
```

Then reinstall inside Kimi (local edits are not picked up automatically):

```
/plugins remove niblet
/plugins install ~/madlexa-skills/plugins/niblet
/new
```

Uninstall:

```
/plugins remove niblet
/new
```

You can also use only the skill without the plugin by symlinking it manually:

```bash
mkdir -p ~/.kimi-code/skills/niblet
ln -s ~/madlexa-skills/plugins/niblet/skills/niblet/SKILL.md \
      ~/.kimi-code/skills/niblet/SKILL.md
```

---

## speculator

Speculator stores project architecture as a knowledge graph of entities and
edges right in your repo, so the agent queries the graph instead of re-reading
dozens of files before writing a single line.

- **TypeScript CLI + MCP server** — graph operations exposed both as a CLI and
  as tools the agent can call directly.
- **Hook-driven context injection** — SessionStart and UserPromptSubmit hooks
  surface relevant graph entities for the current task.
- **Curation agents** — pre-built agents for building and maintaining the graph.

Requires Node.js ≥ 20. See [plugins/speculator/README.md](plugins/speculator/README.md).

### Install speculator

#### Claude Code

```
/plugin marketplace add madlexa/skills
/plugin install speculator@madlexa-skills
```

#### Kimi Code CLI

Speculator is primarily designed around Claude Code hooks and an MCP server.
Kimi support is not documented yet; see `plugins/speculator/README.md` for the
latest status.

---

## Structure

```
skills/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/
    └── <plugin-name>/
        ├── .claude-plugin/plugin.json   # Claude Code manifest
        ├── kimi.plugin.json              # Kimi Code CLI manifest
        ├── README.md
        ├── skills/
        ├── agents/
        ├── hooks/
        └── ...
```

## Platform support

Plugins in this marketplace ship as POSIX shell scripts unless noted otherwise.
They run natively on **macOS** and **Linux**. Windows users need **WSL2**
(recommended) or **Git Bash** — `cmd.exe` and PowerShell are not supported.
See each plugin's README for its specific dependencies.
