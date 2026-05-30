# Speculator

**Stop paying tokens to find your own code.**

Speculator gives Claude a persistent memory of your architecture — stored as a
knowledge graph of entities and edges right in your repo. Claude queries the
graph instead of re-reading dozens of files before writing a single line.

|                     | Without Speculator | With Speculator |
|---------------------|--------------------|-----------------|
| Files read per task | ~40 files          | 0 files         |
| Knows "why"?        | Never              | Always          |
| Finds related code? | Maybe              | Instantly       |
| Tokens per task     | ~12 000            | ~800            |

## Install

```
/plugin marketplace add madlexa/skills
/plugin install speculator@madlexa-skills
```

Or for local development:

```bash
claude --plugin-dir /path/to/madlexa/skills/plugins/speculator
```

## Platform support & requirements

Speculator ships a TypeScript CLI + MCP server (Node.js) plus POSIX shell hooks.
The hooks run natively on **macOS** and **Linux**. On **Windows**, use a
Unix-like shell — **WSL2** (recommended) or **Git Bash** with Claude Code
configured to invoke hooks via `bash`.

### Runtime dependencies

| Tool | Required | Used for |
|---|---|---|
| Node.js (≥ 20) | yes | CLI + MCP server (`dist/cli.js`, `dist/mcp.js`) |
| `bash` (≥ 4) | yes | hooks and CLI wrapper |
| `jq` | yes | parsing hook JSON |
| `git` | yes | project root detection |

Install missing tools before installing the plugin:

```bash
# macOS via Homebrew
brew install jq node

# Debian / Ubuntu
sudo apt install jq nodejs npm
```

## How it works

### 1. Document

Add entities and edges to the graph using the CLI or MCP. Store architecture
decisions, reasons, and relationships — right in your repo.

```bash
$ speculator add entity "auth" "JWT auth middleware"
$ speculator add edge auth user-service uses
```

### 2. Query

Claude asks the graph instead of reading files. One call returns the entity,
all its edges, and the reasons behind every decision.

```bash
$ speculator get auth --facet reason
→ compliance requirement, added 2026-03

$ speculator list edges --from auth
→ user-service, jwt-utils, session-store
```

### 3. Act

Claude makes precise changes — knowing what's connected, why it was built that
way, and what will break. No guessing, no rereading.

## Entities and edges

**Entity** — any named concept that non-engineers use as a noun: `Order`,
`PaymentGateway`, `NotificationTemplate`. Utilities and helpers live as
sections inside the entity that owns them.

**Edge** `A → B` — a documented dependency. Typed sections:

| Section           | Content                                                           |
|-------------------|-------------------------------------------------------------------|
| `## Human`        | WHY this dependency exists — the decision, constraint, or history |
| `## Code`         | WHERE — file:line, class, method, call chain in order             |
| `## Context`      | Rejected alternatives and non-obvious constraints behind the WHY  |
| `## Db`           | Table, fields, SQL/ORM contract                                   |
| `## Rest`         | HTTP method, path, key params                                     |
| `## Queue`        | Topic, message schema, ordering guarantees                        |
| `## Event`        | Event type, payload shape, producer/consumer                      |
| `## Cache`        | Key pattern, TTL, invalidation                                    |
| `## Known Issues` | Tech debt, workarounds, TODO items for this dependency            |

## CLI reference

```bash
speculator init knowledge                       # create a new KB (--no-example to skip the sample)
speculator search "keywords"
speculator get entity-slug
speculator get from-slug to-slug
speculator get entity-slug --facet Human        # also: --depth N, --verbose
speculator get entity-slug --depth 2
speculator list entities                        # also: --tag <tag>
speculator list edges                           # also: --from <slug> --to <slug> --stale <days> --stale-relative
speculator add entity "Name" "summary for search"
speculator add edge from-slug to-slug relation
speculator add alias entity-slug new-alias      # remove with: speculator remove-alias <slug> <alias>
speculator update from-slug to-slug Code "file:line — method"
speculator update entity-slug --metadata summary "new summary"
speculator import graph.yaml                     # bulk-import entities + edges
speculator export mermaid                        # or: dot | json
speculator remove entity-slug                    # delete entity + its edges (or: remove from-slug to-slug)
speculator index rebuild                         # regenerate INDEX files
speculator stats
speculator validate
```

The KB directory defaults to `./knowledge`. Override per-invocation with
`--dir <path>` or globally with the `SPECULATOR_DIR` environment variable
(both the CLI and the MCP server respect it).

## Hooks

The plugin registers two best-effort, non-blocking hooks (see
`hooks/hooks.json`). Both exit 0 silently when Node.js, the CLI, or a
populated knowledge base is missing — they never block a session.

| Hook | Fires on | What it does |
|---|---|---|
| `on_session_start.sh` | `SessionStart` | Emits a compact `speculator stats` overview (entity/edge counts, most-connected entities) so the agent knows a graph KB exists for this project. |
| `on_prompt_submit.sh` | `UserPromptSubmit` | Runs your prompt through `speculator search` and injects matching entities/edges as context — zero manual lookup. The prompt is passed as a single argv (never eval'd) and capped at 400 chars. |

The hooks resolve the project root from the hook's stdin payload, locate the
knowledge base, and shell out to the bundled CLI. Writing to the KB stays an
explicit agent action — the hooks only read.

## MCP server

When installed as a plugin, the MCP server is registered automatically via the
plugin's `.mcp.json` — no manual setup. It exposes the same graph operations as
the CLI (get, search, add_entity, add_edge, …) as MCP tools the agent can call
directly, plus the `usage-guide` and `bootstrap` prompts. The knowledge base
defaults to `./knowledge` (relative to the project) and honours `SPECULATOR_DIR`.

To wire it up manually outside the plugin (e.g. a standalone checkout), add to
your `.mcp.json` with an absolute path to the built server — `npm run build`
produces `dist/mcp.js`:

```json
{
  "mcpServers": {
    "speculator": {
      "command": "node",
      "args": [
        "/absolute/path/to/speculator/dist/mcp.js",
        "--dir",
        "/absolute/path/to/project/knowledge"
      ]
    }
  }
}
```

## License

MIT
