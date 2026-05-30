---
name: speculator
description: Query the project's domain knowledge graph before grepping or reading code. Use for any task involving business concepts, inter-service dependencies, data flow, bug fixes, features, or refactors that change behavior. Stores architecture as Markdown entities and edges; query with the `speculator` CLI (search/get/list/update).
---

# Speculator — Knowledge Graph Protocol

Speculator stores domain knowledge as Markdown files. Query it before grepping or reading code.

**When to use:** any task involving business concepts, inter-service dependencies, data flow,
bug fixes, features, or refactors that change behavior.

**Entities** — named domain concepts that non-engineers use as nouns:
`Order`, `PaymentGateway`, `NotificationTemplate`.
Not entities: utility classes, helpers, DTOs — document these inside the entity that owns them.

**Edges** — documented dependencies between entities. Each edge has typed sections:
- `## Human` — WHY this dependency exists (decision, constraint, history). Always fill this.
- `## Code` — WHERE: file:line, class, method, call chain in execution order. Always fill this.
- `## Db` / `## Rest` / `## Queue` / `## Cache` — fill when applicable.

**Session flow:**
1. New task → `search("keywords from task description")`
2. Found entity → `get("slug")` or `get("from", "to")` for edge detail
3. Focused question → `search("query", block="Human")` or `block="Code"`
4. After editing code → `update("from", "to", "Code", "file:line — method")`
5. Verified edge unchanged → `update("from", "to")` (touch, no content)

Quick reference (CLI):
```
speculator search "keywords"
speculator get entity-slug
speculator get from-slug to-slug --facet Human
speculator update from-slug to-slug Code "file:line — method"
speculator list entities
```

> The `speculator` command is provided by `bin/speculator` in this plugin. When the
> plugin is installed it resolves the bundled `dist/cli.js` automatically. For local
> development run `npm run build` in the plugin directory first.

## Rule: KB is the single source of truth for operational facts

If the `UserPromptSubmit` hook or a manual `search` returned a result — **use it directly**.
Do not run `grep`/`Read` to confirm information the KB already provided.

## Specialist agents

For deeper work, three agents ship with this plugin:
- **Speculator AI Engineer** — KB entry quality and LLM context engineering.
- **MCP Protocol Engineer** — MCP tool registrations, descriptions, and schemas.
- **TypeScript CLI Developer** — the TypeScript CLI/MCP implementation.
