#!/usr/bin/env node
import {McpServer} from "@modelcontextprotocol/sdk/server/mcp.js";
import {StdioServerTransport} from "@modelcontextprotocol/sdk/server/stdio.js";
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import {allTools} from "./commands/registry";
import {ENTITY_CONCEPT, EDGE_SECTIONS, SESSION_FLOW} from "./lib/prompts";

// Parse --dir from argv
const cliArgs = process.argv.slice(2);
const dirIdx = cliArgs.indexOf("--dir");
const dir = dirIdx !== -1
    ? cliArgs[dirIdx + 1]
    : (process.env.SPECULATOR_DIR ?? "./knowledge");

// Typed content helpers — avoids `as const` at every call site
function textContent(text: string) {
    return {type: "text" as const, text};
}

const SERVER_INSTRUCTIONS = `# Speculator — project knowledge graph

Speculator is the project's domain knowledge graph stored as Markdown files.

Use Speculator before reading or editing product code when the task involves:
- business or domain concepts
- dependencies between modules, services, or entities
- data flow across DB, REST, events, queues, or cache
- bug fixes, features, or refactors that change behavior

Preferred lookup order:
1. search(query) — use words from the task description, bug report, or spec
2. get(slug) — inspect one entity
3. get(slug, to) — inspect a dependency between two entities
4. list_entities() / list_edges() — only when graph state is unclear

After code changes that affect a dependency between entities:
- update(slug, to, "Code", "...") — record new code locations and call chain
- update(slug, to, "Human", "...") — when the reason or decision changed
- update(slug, to) — when the dependency was verified but not changed

If the concept is missing, add it before editing code:
- add_entity(name, summary) then add_edge(from, to, relation)
- document the edge with at least Human and Code sections

Do not use Speculator for:
- trivial local implementation details (private methods, formatters)
- changes limited to .claude config, hooks, build tooling, or the knowledge graph itself`;

const USAGE_GUIDE = `# Speculator — Knowledge Graph

## Why this exists

Code tells you *what* happens. The knowledge graph tells you *why* and *where* —
the decisions behind the code, the contracts between components, the history that
explains why something was built in a non-obvious way.

Without a graph you grep. Grepping finds files; it does not find the reason a
payment record is written before the gateway call, or why two services share
a database table, or what breaks if you change a queue message format.

**The graph is a map. Query the map before you open any file.**

## What is an entity

${ENTITY_CONCEPT}

Not every class deserves an entity. A utility or helper lives as a section
inside the entity that *owns* it. Create an entity when a concept has its own
lifecycle, its own rules, or its own dependencies.

**Why entities matter:** The entity is the handle that connects everything —
query it once and you see all the edges: what it uses, what uses it, what tables,
what endpoints, what events. Without entities you would have to grep separately
for each relationship.

## What is an edge

An edge \`A → B\` means: A's code depends on B in a documented way.
The relation label names the kind of dependency:
\`uses\`, \`reads_from\`, \`publishes_to\`, \`validates\`, \`renders\`, \`calls\`, \`stores_in\`

An edge is the place where you write what cannot be read from the code in
30 seconds.

${EDGE_SECTIONS}

### What good content looks like

**Good \`## Human\`** — explains a non-obvious decision, not a restatement:
\`\`\`
Payment record is written BEFORE the gateway call (not after) so we always
know the intent even when the gateway times out. This is the idempotency
checkpoint: on retry, we check if a record in status=PENDING exists for the
same order and reuse it instead of charging twice. Introduced after the
Black Friday 2023 double-charge incident.
\`\`\`

**Bad \`## Human\`** — restates the code, adds nothing:
\`\`\`
PaymentService uses PaymentRepository to store payments.
\`\`\`

**Good \`## Code\`** — exact file, method, call chain:
\`\`\`
PaymentService.processPayment(request)                    // payment/PaymentService.java:89
  → PaymentRepository.createPending(record)               // payment/PaymentRepository.java:45
  → GatewayClient.charge(request)                         // gateway/GatewayClient.java:112
  → PaymentRepository.updateStatus(id, result)            // payment/PaymentRepository.java:67
\`\`\`

**Bad \`## Code\`** — too vague to navigate to:
\`\`\`
PaymentService depends on PaymentRepository and GatewayClient.
\`\`\`

## Querying by section type — visibility slices

Each section type is a separate view of the same graph. Use the \`block\` parameter
to answer specific kinds of questions without loading irrelevant content:

\`\`\`
search("payment", block="Human")   → WHY slice: decisions and history about payments
search("payment", block="Code")    → WHERE slice: all files and methods for payments
search("order", block="Db")        → SCHEMA slice: all tables related to orders
search("notification", block="Rest") → API slice: all endpoints for notifications
\`\`\`

\`get(slug, facet="Human")\` — read just the Human section of one entity/edge.
\`get(slug, depth=2)\` — BFS neighborhood: see everything reachable within 2 hops.

Use slices when you have a focused question. Use \`search(query)\` (no block) when
you do not know which section has the answer.

## Example: full task flow

**Task**: fix the feedback message text shown to users.

\`\`\`
search("feedback message")
  → entity: message    entity: feedback-event
    edge:   message → feedback-event [renders]

get("message", "feedback-event")
  → ## Human
    Messages are built from a stored template so product managers
    can change the text without a deploy.
    ## Code
    MessageService.java:buildFeedbackMessage()
      calls EventRepository.findByType("FEEDBACK").getFeedbackTemplate()
    ## Db
    Table: event  |  field: feedback_template  |  type: VARCHAR(2048)
\`\`\`

Result: 1 method, 1 DB field. No grep, no file browsing.

After the fix:
\`\`\`
update("message", "feedback-event", "Code",
  "MessageService.java:buildFeedbackMessage() — same, updated template fallback logic")
\`\`\`

## What NOT to document

- Private methods and internal helpers — readable from the file in seconds
- Variable names, function signatures — they change often, graph goes stale fast
- Counts ("3 services use this") — always wrong after the next refactor
- What is obvious from the class or file name

**Rule:** if you can infer it from reading the file in 30 seconds, don't document it.
Document what you cannot infer: history, decisions, cross-service contracts.

## When you cannot find something

\`get("validator")\` returns "not found" → Speculator suggests close matches automatically.
If the suggestion is correct, add an alias so future lookups work:

\`\`\`
add_alias("model-validator", "validator")
\`\`\`

Do this immediately — it keeps the graph navigable for the next agent.

If nothing close exists, the concept is not documented yet. Find it in code,
then add entity + edge before continuing.

## Session flow

${SESSION_FLOW}

## API reference

\`\`\`
# Read
list_entities()                        → all entities (name, slug, summary)
list_edges()                           → all edges (from, to, relation, last-verified)
get(slug)                              → entity doc + connected edges
get(slug, facet="Section")             → one ## section of an entity
get(slug, to)                          → edge doc or BFS path between two entities
get(slug, to, facet="Section")         → one ## section of an edge
get(slug, depth=N)                     → BFS neighborhood table (N hops)
search(query)                          → full-text search across all entities and edges
search(query, block="Human")           → search only in Human sections
search(query, block="Code,Db")         → search in Code and Db sections

# Write
add_entity(name, summary)              → new entity (summary = words from task descriptions)
add_edge(from, to, relation)           → new edge
add_alias(slug, alias)                 → add lookup alias
remove_alias(slug, alias)              → remove alias
update(slug, section, content)         → update entity section
update(slug, to, section, content)     → update edge section
update(slug, to)                       → touch edge (last-verified = today)
remove(name)                           → delete entity + all edges
remove(name, name2)                    → delete just the edge between two entities
index_rebuild()                        → rebuild INDEX files from disk
\`\`\`
`;

const BOOTSTRAP_PROJECT_GRAPH = `# Bootstrap the Speculator graph for this repository

Follow these steps in order.

## 1. Confirm Speculator is installed and has a knowledge base

You are reading this through the Speculator MCP server, so the plugin is
already installed — its hooks and MCP server are registered automatically by
the plugin. Do **not** run any \`curl\` installer or \`tools/speculator.cmd\`;
those belong to the old standalone distribution and would create a second,
conflicting setup.

You only need a knowledge base to write into. If \`./knowledge\` does not exist
yet, create it once from your shell:

\`\`\`bash
speculator init knowledge      # creates entities/, edges/, and INDEX files
\`\`\`

If you configured a different \`--dir\`/\`SPECULATOR_DIR\`, init that path instead.

## 2. Bootstrap the first slice of the graph

Start with 5–10 domain concepts that appear in bug reports, task descriptions, and product specs:

1. \`mcp__speculator__list_entities()\` — see what's already documented
2. For each key concept: \`mcp__speculator__add_entity(name="...", summary="...")\`
   Write the summary using words from task descriptions, not implementation names.
3. For each major dependency: \`mcp__speculator__add_edge(from="...", to="...", relation="...")\`
4. For each edge: add \`Human\` (why) and \`Code\` (where) sections at minimum

Stop after the first coherent slice. The graph grows incrementally during future tasks.
`;

const server = new McpServer(
    {name: "speculator", version: "0.1.5"},
    {capabilities: {tools: {}, prompts: {}}, instructions: SERVER_INSTRUCTIONS}
);

server.registerPrompt("usage-guide", {
    description: "How and when to use Speculator knowledge graph tools",
}, async () => ({
    description: "How and when to use Speculator knowledge graph tools",
    messages: [
        {
            role: "user" as const,
            content: {type: "text" as const, text: USAGE_GUIDE},
        },
    ],
}));

server.registerPrompt("bootstrap", {
    description: "One-time project setup: initialize knowledge base, configure CLAUDE.md, and install enforcement hooks",
}, async () => ({
    description: "One-time project setup: initialize knowledge base, configure CLAUDE.md, and install enforcement hooks",
    messages: [
        {
            role: "user" as const,
            content: {type: "text" as const, text: BOOTSTRAP_PROJECT_GRAPH},
        },
    ],
}));

server.server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: allTools.map((cmd) => ({
        name: cmd.name,
        description: cmd.description,
        inputSchema: cmd.type().schema(),
    })),
}));

server.server.setRequestHandler(CallToolRequestSchema, async ({params}) => {
    const {name, arguments: rawArgs} = params;
    const tool = allTools.find((t) => t.name === name);

    if (!tool) {
        return {isError: true, content: [textContent(`Unknown tool: ${name}`)]};
    }

    try {
        const result = await tool.run(rawArgs ?? {}, dir);
        return {content: [textContent(result)]};
    } catch (e) {
        return {isError: true, content: [textContent(e instanceof Error ? e.message : String(e))]};
    }
});

process.on("uncaughtException", () => {
    process.stderr.write("Speculator MCP server crashed. Reconnect it via your MCP client settings.\n");
    process.exit(1);
});
process.on("unhandledRejection", () => {
    process.stderr.write("Speculator MCP server crashed. Reconnect it via your MCP client settings.\n");
    process.exit(1);
});

const transport = new StdioServerTransport();
server.connect(transport).catch(() => {
    process.stderr.write("Speculator MCP server failed to start. Reconnect it via your MCP client settings.\n");
    process.exit(1);
});
