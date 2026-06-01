---
name: repackage-as-plugin
description: Repackage a standalone CLI/MCP project into a Claude Code plugin under plugins/<name>/ in this marketplace repo. Use when migrating an external tool (TypeScript CLI, MCP server, etc.) into a publishable plugin, mirroring the plugins/niblet reference layout.
user-invocable: false
---

# Repackage a standalone project as a Claude Code plugin

## When to use
A standalone tool (e.g. a TypeScript CLI + MCP server) needs to become a plugin under `plugins/<name>/` so it can ship via the root `.claude-plugin/marketplace.json`. Use `plugins/niblet/` as the canonical reference — do not invent new conventions.

## Steps
1. **Base structure.** Create `plugins/<name>/.claude-plugin/plugin.json` (name, version, description), `README.md`, and `package.json` (copy deps from the source project). Validate `jq -e` parses both; assert versions match.
2. **Source.** Copy `src/**` and `tsconfig.json` verbatim if the internal layout is unchanged (relative imports `./commands ./lib` need no rewrite). Verify `npx tsc --noEmit` is clean.
3. **bin wrapper.** Create `bin/<name>` — a bash wrapper that runs the compiled `dist/cli.js` via node, resolving `$CLAUDE_PLUGIN_ROOT/dist/cli.js` first, then `<plugin-root>/dist/cli.js` (from `BASH_SOURCE`). `chmod +x`. Distinct exit codes for node-missing vs dist-missing.
4. **Hooks.** Create `hooks/hooks.json` (e.g. `SessionStart` + `UserPromptSubmit`) and `hooks/*.sh`. `chmod +x`. Each hook must exit 0 on an empty environment.
5. **Skill + agents.** Create `skills/<name>/SKILL.md` (YAML frontmatter with name + description) and copy agents into `agents/*.md`. Re-point agent CLI references to `bin/<name>`. Verify every frontmatter has name + description.
6. **lib/.** Create `lib/paths.sh` (project-root / kb-dir / stdin-field helpers) and any `lib/*.sh` the hooks call. Source-test without errors. Delete any helper copied from the template that the hooks do not actually call.
7. **Build + smoke test.** Add `build`/`typecheck`/`test` scripts to `package.json` (`test` runs `bash tests/smoke_test.sh`; keep unit tests under `test:unit`). Build with esbuild to `dist/`. Write `tests/smoke_test.sh` that delegates to per-area test scripts (bin/hooks/frontmatter/lib) and asserts manifest validity + version agreement.
8. **MCP registration.** If the project advertises an MCP server, add `plugins/<name>/.mcp.json` registering it with `${CLAUDE_PLUGIN_ROOT}/dist/mcp.js`. A relative path will NOT resolve for an installed plugin.
9. **Marketplace + root docs.** Add the plugin to root `.claude-plugin/marketplace.json` (name, version, `source ./plugins/<name>`, keywords) and to root `README.md`. Test that `marketplace.json` is valid and the source resolves to the plugin dir.
10. **Verify.** Run full `npm test`, `npx tsc --noEmit`, confirm version agreement across plugin.json/marketplace.json/package.json, and that all hooks exit 0.

## Why this works
Mirroring an existing, tested plugin (`plugins/niblet/`) means the harness conventions (`CLAUDE_PLUGIN_ROOT`, hooks.json schema, smoke-test delegation) are already known-good. The common failure modes are covered by the worked example `docs/plans/completed/2026-05-30-migrate-speculator-plugin.md` and by KB `niblet-plugin-overview.md`: unregistered MCP server, relative paths in wrappers/docs, idempotency-marker mismatches, version drift across manifests, and dead helpers carried from the template.
