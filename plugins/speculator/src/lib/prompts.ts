/**
 * Shared prompt fragments — used in USAGE_GUIDE and the bootstrap prompt (mcp.ts).
 * Edit here; both surfaces update automatically.
 */

/** What an entity is — content without heading */
export const ENTITY_CONCEPT = `A named domain concept — almost always **one word**.

**The single-word rule is the key test:**
- If you can name it in one word → it's an entity: \`order\`, \`payment\`, \`gateway\`
- If you need two words → it's an edge, not an entity

\`PaymentGateway\` → not one entity. It's an edge: \`payment\` → \`gateway\` [processed_by]
\`SurveyPage\` → not one entity. It's an edge: \`survey\` → \`page\` [rendered_on]
\`OrderNotification\` → not one entity. It's an edge: \`order\` → \`notification\` [triggers]

Multi-word names reveal two domain concepts that need a relationship — model that relationship explicitly.

✓ Entity: \`order\`, \`payment\`, \`survey\`, \`notification\`, \`gateway\`, \`user\`, \`report\`
✗ Not entity: utilities, private helpers, DTOs — document inside the entity that owns them.`;

/** Edge typed sections — content without heading */
export const EDGE_SECTIONS = `Each edge has typed sections:
| Section | What to write | When |
|---------|--------------|------|
| \`## Human\` | WHY this dependency exists (decision, constraint, history) | Always |
| \`## Code\` | WHERE: file:line, class, method, call chain in execution order | Always |
| \`## Context\` | Rejected alternatives and non-obvious constraints behind the decision | When WHY needs explanation of what was NOT chosen |
| \`## Db\` | Table, schema, SQL/ORM contract | When DB |
| \`## Rest\` | HTTP method, path, key params, response shape | When HTTP |
| \`## Queue\` | Topic, message schema, ordering guarantees | When async |
| \`## Event\` | Event type, payload shape, producer/consumer | When event-driven |
| \`## Cache\` | Key pattern, TTL, who invalidates and when | When cache |
| \`## Known Issues\` | Tech debt, workarounds, TODO items for this dependency | When there are known problems |`;

/** Session flow steps — identical in CLI and MCP contexts */
export const SESSION_FLOW = `1. New task → \`search("keywords")\` — use words from the task description
2. Found entity → \`get(slug)\` or \`get(slug, to)\` for edge detail
3. Scope unclear → \`get(slug, depth=2)\` to see neighbors
4. Focused question → \`search("query", block="Human|Code|Db")\`
5. After editing code → \`update(slug, to, "Code", "file:line — method")\`
6. Verified edge unchanged → \`update(slug, to)\` (touch only)`;
