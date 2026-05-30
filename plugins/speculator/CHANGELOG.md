# Changelog

## [0.1.5] — 2026-04-09

**Packaging**
- Repackaged as a Claude Code plugin under `plugins/speculator/` in the
  `madlexa/skills` marketplace: `.claude-plugin/plugin.json` manifest,
  `hooks/hooks.json` (`SessionStart` + `UserPromptSubmit`), a `bin/speculator`
  wrapper, `lib/*.sh` shared shell helpers, and `tests/smoke_test.sh`. Install
  via `/plugin install speculator@madlexa-skills`.
- Removed the standalone `setup` command (`src/commands/setup.ts`) and its
  `src/lib/constants.ts` (`RELEASE_BASE`/`REPO`). As a plugin, hooks register
  through `hooks/hooks.json` and the MCP server through `.mcp.json`; the old
  `setup` downloaded assets from the standalone GitHub releases and wrote a
  duplicate hook registration into `.claude/settings.json`, which would
  conflict with the plugin's own configuration.

**Features**
- `EdgeFrontmatter.deprecated?: string` — mark edges as historical without deleting them; `validate` skips ref checks for deprecated edges and reports count separately
- `agents/speculator-ai-engineer.md` — LLM context engineering specialist (KB quality, tool descriptions, hook output)
- `agents/speculator-typescript-cli-developer.md` — TypeScript CLI specialist with full codebase context
- `agents/speculator-mcp-protocol-engineer.md` — MCP tool description and protocol specialist
- `.github/workflows/release.yml` — agent files included as release assets

**Improvements**
- `ENTITY_CONCEPT` prompt — one-word rule is now the lead definition; multi-word names show concrete edge transformations (`PaymentGateway` → edge, `SurveyPage` → edge)
- `EDGE_SECTIONS` — added `## Context` (rejected alternatives) and `## Known Issues` (tech debt) to the typed sections table
- `AGENTS_BLOCK` — documents `deprecated` edge field
- `init` example entity — includes `## Context` section template
- Hook `UserPromptSubmit` — no-results message explains why KB returned nothing and what to do
- Hook `PostToolUse:search` — minimum query length 4 chars (eliminates noise from short filenames like `get`, `add`)

## [0.1.4] — 2026-03-31

**Refactor**
- `src/lib/prompts.ts` — new shared module: `ENTITY_CONCEPT`, `EDGE_SECTIONS`, `SESSION_FLOW` constants eliminate duplication between `AGENTS_BLOCK` and `USAGE_GUIDE`
- `setup.ts`, `mcp.ts` — import from `prompts.ts`; prompt content now has a single source of truth

**Docs**
- Entity naming rule "entity = 1 word (one concept)" added to all four prompt surfaces: `USAGE_GUIDE`, `AGENTS_BLOCK`, `docs/graph-modeling.md`, `knowledge/entities/storage.md`
- Compound name examples corrected: `surveyPage` → two entities `survey` + `page` + edge
- `docs/graph-modeling.md` Rule 1 and Anti-patterns table updated accordingly

---

## [0.1.3] — 2026-03-30

**Features**
- Single-command install: `curl -fsSL .../install.cmd | bash` — downloads wrapper, runs setup and init
- `setup` now writes files directly (hooks, AGENTS.md, settings.json, .gitignore) instead of printing instructions
- `tools/install.cmd` — unified dual bash/batch installer (replaces `install.sh` + `install.ps1`)
- `.claude/hooks/speculator.cmd` — hook renamed from `speculator.sh` to `speculator.cmd` for native Windows support
- `SPECULATOR_RELEASE_BASE` env var — override GitHub Releases URL for self-hosted mirrors (Artifactory, etc.); applies to TypeScript code and all shell scripts
- `src/lib/constants.ts` — single source of truth for release URL
- `init` is now idempotent: non-empty directory returns success instead of error

**Refactor**
- `setup.ts`: removed ~200 lines of embedded shell scripts; hook and wrapper downloaded at runtime from `RELEASE_BASE`
- `mcp.ts`: removed embedded `BOOTSTRAP_PROJECT_GRAPH` shell blocks; replaced with reference to `setup` command

---

## [0.1.2] — 2026-03-26

**Fixes**
- Hook `UserPromptSubmit`: removed EXEMPT/NEEDS keyword gating — always searches KB; injects context if found, hints for manual search if empty
- `tests/helpers.ts`: fixed TypeScript typecheck error (`result.content` typed as `unknown`)

---

## [0.1.1] — 2026-03-26

**New commands / flags**
- `update --metadata <field> <value>` — update YAML frontmatter (summary, tags, …). Protected: id, slug, type, created
- `list edges --stale-relative` — edges whose file is older than an adjacent entity's mtime (phantom edge detection)
- `import <file.yaml>` — bulk-import entities and edges from YAML, skips duplicates
- `get --verbose` — show Human section snippet for each connected edge
- `init --no-example` — skip example entity on init

**Fixes**
- Edge display: `→` replaced with `↔` to reflect bidirectionality
- Hook dirty: false-positive "No results for: X" no longer shown as a match; branches to `add entity` hint for new files
- Hook: MCP notation (`mcp__speculator__update`) replaced with CLI equivalents throughout
- Hook: synced with repo's `.claude/hooks/speculator.sh` — added `should_ignore()`, `.specignore` support, `--color=never`
- `search`: returns empty string on no results (was returning "No results for: …")
- `init`: errors on non-empty target directory

**Docs**
- `docs/graph-modeling.md` — new guide: 5 modeling rules, anti-patterns table
- `setup` AGENTS_BLOCK: graph design rules, adjacent-entity protocol, Known Issues convention, existing-edge rule
- `knowledge/entities/cli.md`: `## Graph Design` section, `--metadata` examples

---

## [0.1.0] — 2026-03-24

Initial release.
