# Project instructions

This repository is a marketplace of agent plugins for Claude Code and Kimi Code CLI. Treat it as a monorepo where each plugin lives under `plugins/<name>/` and ships its own manifest, skills, agents, hooks, and tests.

## Niblet maintenance pipeline

This project uses the `niblet` knowledge-keeper plugin to capture findings, consolidate skills/KB, and auto-promote safe proposals. The pipeline is periodic and agent-driven.

### Configuration

Project-level settings are in `.niblet/config`:

- `NIBLET_AUTO_PROMOTE=1` — safe project-scope proposals are auto-promoted.
- `NIBLET_KB_DISTILL_COUNT=15` / `NIBLET_KB_DISTILL_BYTES=150000` — KB compact thresholds.
- `NIBLET_ARTIFACT_COMPACT_COUNT=10` / `NIBLET_ARTIFACT_COMPACT_BYTES=200000` — skill/agent/command/script compact thresholds.
- `NIBLET_MEMORY_COMPACT_COUNT=5` — memory feedback compact threshold.

### End-of-task maintenance (no timer cron)

At the end of any non-trivial task (roughly ≥ 8 file-mutating tool calls, or when the user says "save findings" / "сохрани выводы"):

1. Run `niblet-deep` to extract reusable patterns from the session log.
2. Run `niblet-wrap-up --project-root <project>` to get a concise status + suggestions.
3. If `niblet-wrap-up` suggests a sub-agent, propose the command to the user instead of running it silently:
   - `niblet-code-walker` — source files changed since last walk.
   - `niblet-distill` — KB/memory/artifact thresholds exceeded.
   - `niblet-deep` / `niblet-audit` — corresponding queue has pending entries.
4. Only auto-spawn sub-agents when the user explicitly asks to save findings or a queued checkpoint already exists.
5. Log every file mutation via `niblet_log`.

### What gets auto-written vs proposed

- **Auto-write tier**: KB entries, memory feedback, KB merges/updates/deprecations.
- **Proposal tier**: skills, agents, commands, scripts, `CLAUDE.md`/`AGENTS.md` edits, global-scope actions.

### How to evolve skills/agents/KB

- **Create**: emit `CREATE_SKILL`, `CREATE_AGENT`, or `CREATE_COMMAND` — staged as a proposal.
- **Refactor/update**: emit `UPDATE_SKILL`, `UPDATE_AGENT`, or `UPDATE_COMMAND` — staged as a proposal with a `.niblet-backup`.
- **Merge**: emit `MERGE_SKILL` or `MERGE_AGENT` with the combined content — staged as a proposal with a `.niblet-backup`.
- **KB merge**: emit `MERGE_KB_ENTRY` to overwrite an existing entry with consolidated content.
- **KB deprecation**: emit `DEPRECATE_KB_ENTRY` for stale entries.

### Capturing user rules

When the user states an "always/never" rule, describes a pipeline step, or repeats a correction, route it immediately:
- Reusable workflow → `CREATE_SKILL`.
- Project-wide invariant or pipeline rule → `UPDATE_CLAUDE` or `UPDATE_AGENTS`.
- One-time correction → `UPDATE_MEMORY`.

## Build/test conventions

- Each plugin should have its own test script under `plugins/<name>/tests/`.
- For niblet, run `bash plugins/niblet/tests/smoke_test.sh` before declaring changes complete.
- Do not modify files outside the working directory without explicit user permission.
