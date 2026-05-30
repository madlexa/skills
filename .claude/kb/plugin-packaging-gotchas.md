# Claude Code plugin packaging gotchas

Discovered while repackaging the standalone `speculator` TS/MCP project into `plugins/speculator/` (commits 617eccb, a53bf44). Each was a real defect caught in review.

## 1. An advertised MCP server must be registered with `.mcp.json`
`plugin.json`, `marketplace.json`, and `README` all named a `speculator` MCP server, but nothing wired it on install. A plugin's MCP server is registered via `plugins/<name>/.mcp.json`:

```json
{"mcpServers": {"speculator": {"command": "node", "args": ["${CLAUDE_PLUGIN_ROOT}/dist/mcp.js"]}}}
```

Use `${CLAUDE_PLUGIN_ROOT}` — a path relative to cwd (e.g. `dist/mcp.js`) will not resolve for an installed plugin. Add a smoke-test section asserting `.mcp.json` is valid JSON and registers the server.

## 2. bin wrappers and docs must use `$CLAUDE_PLUGIN_ROOT`, not relative paths
The `bin/speculator` wrapper resolves the compiled CLI as `$CLAUDE_PLUGIN_ROOT/dist/cli.js` first, then falls back to `<plugin-root>/dist/cli.js` (derived from `BASH_SOURCE`) for local dev. README MCP examples using a relative `dist/mcp.js` were wrong for installed plugins.

## 3. Idempotency guards must match the actual artifact name
`setup.ts` checked for an existing `speculator.sh` marker but hooks were written as `speculator.cmd`, so re-running `setup` double-registered hook entries. When a setup step is meant to be idempotent, the guard must check the exact filename the step writes.

## 4. Version must agree across all manifests
Keep `version` identical in `plugin.json`, root `.claude-plugin/marketplace.json`, and `package.json` (speculator: `0.1.5`). Add a smoke-test assertion that the three agree.

## 5. Don't leave dead helpers from the template
`lib/paths.sh` carried an unused `speculator_plugin_root` copied from niblet; hooks resolve root inline per the niblet pattern. Drop helpers the hooks don't actually call.
