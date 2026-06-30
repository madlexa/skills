# Changelog

## 0.6.0

- **Ratchet loop.** `niblet-ratchet` auto-promotes `UPDATE_*` proposals when the
  live artifact is underperforming (usage >= 3, success_rate < 0.5). CREATE_*
  proposals always stay in review. Every promotion still saves the previous
  version to `.niblet/versions/`.
- **Metrics dashboard.** `niblet-metrics` aggregates skill and pipeline usage
  from `.niblet/metrics/*.jsonl` and flags underperforming artifacts.
- **File-based versioning.** `niblet-versioning` / `niblet-revert` keep
  timestamped copies under `.niblet/versions/`; `niblet-promote` saves a version
  before overwriting live artifacts.
- **Unified Python core.** Newer tools (`capture-task`, `metrics`, `versioning`,
  `ratchet`, `revert`, `pipelines`, `capture-read`) share a single Python package
  under `src/niblet/`. The `bin/` scripts are thin wrappers around
  `python3 -m niblet <subcommand>`.
- **KB as side effect of reading.** `niblet-capture-read` (Claude hook + Kimi MCP
  tool) counts reads/edits per component. Once a component reaches the threshold,
  a code-walker checkpoint is queued so the next prompt can spawn the sub-agent
  and distill a component-level KB entry.
- **Pipelines as first-class citizens.** Reusable workflows live under
  `.niblet/pipelines/` and can be listed, shown, and run via `niblet-pipelines`.
  Usage is recorded in `.niblet/metrics/pipelines.jsonl`.
- **Autonomous maintenance mode.** `niblet-maintain` runs ratchet, gardener, and
  a queue report in one pass. A daily cron reminder can invoke it automatically.

## 0.4.1

- **Kimi Code CLI support.** Niblet now ships as a Kimi Code CLI plugin
  (`kimi.plugin.json`) with a bundled MCP server exposing four tools:
  `niblet_log`, `niblet_apply`, `niblet_status`, and `niblet_promote`.
  The skill (`SKILL.md`) contains Kimi-specific instructions: explicit logging after
  file mutations, session-start KB index, and session-end deep analysis.
- **Interruption capture.** When execution is stopped (Ctrl+C, TaskStop) or a plan is
  rejected/revised, the agent is instructed to immediately write the user's correction
  to `memory/feedback_interruptions.md`.
- **"wtf" capture.** Negative-sentiment triggers (`wtf`, `не так`, `переделай`, `стоп`,
  `заново`, etc.) are immediately captured in `memory/feedback_wtf.md` so the same
  mistake is never repeated.
- **Runtime-aware artifact paths.** `lib/paths.sh` now auto-detects Kimi vs Claude and
  resolves KB/memory/skills directories to `.kimi/` or `.claude/` accordingly.
- **New tool wrapper scripts.** `bin/niblet-log`, `bin/niblet-apply-kimi`,
  `bin/niblet-status-kimi`, `bin/niblet-promote-kimi` bridge the Kimi plugin stdin
  protocol to the canonical POSIX helpers. All Kimi wrappers now force
  `NIBLET_RUNTIME=kimi`, and `niblet-promote-kimi` runs `niblet-promote` from the
  project root so containment checks resolve to `.kimi/` paths.
- **Removed legacy `plugin.json`.** The old Python `kimi-cli` tool manifest is gone;
  `kimi-code` users install via `/plugins install <path>` using `kimi.plugin.json`.

## 0.3.1

Checkpoints were blocking, noisy, and self-perpetuating: they fired on the user's
first prompt ahead of the actual task, demanded a sub-agent + visible JSON even when
the result was `NOTHING`, and enqueued a fresh DEEP job for every session — so the
queue never drained and the first prompt of nearly every session got hijacked. Under
load this surfaced as `API Error: Overloaded` mid-task and a stream of `NOTHING` JSON
files in the chat.

- **Gate DEEP enqueue on real work** (`on_session_end.sh`, `on_stop.sh` safety-net).
  A session must have ≥ `NIBLET_DEEP_MIN_TOOLCALLS` (default 8) post-phase tool calls
  in its raw log before a DEEP job is queued. Breaks the self-perpetuating queue and
  stops trivial sessions (and checkpoint-only sessions) from seeding `NOTHING` work.
  Set `NIBLET_DEEP_MIN_TOOLCALLS=0` to restore the old unconditional behavior.
- **Gate the FAST marker on file mutations** (`on_stop.sh`). `PENDING_FAST` is now set
  only on turns that actually edited project files (Edit/Write/MultiEdit/NotebookEdit),
  not every turn. Kill-switch: `NIBLET_FAST_ON_EDIT_ONLY=0`.
- **Checkpoints are non-blocking and silent** (`on_prompt_submit.sh`). All four
  reminders now tell the agent to handle the user's request FIRST, process the
  checkpoint only afterward (or skip it entirely if mid-task), never paste raw JSON
  action bodies into replies, and — on a `NOTHING` result — silently delete the queue
  entry instead of writing a `NOTHING` file or narrating it.
- **Sweep abandoned claims** (`on_prompt_submit.sh`). `*.claimed-*` queue files older
  than `NIBLET_CLAIM_STALE_HOURS` (default 24h) are deleted, so dead checkpoints no
  longer litter the queues or keep the status line nagging.

## 0.3.0

Initial tracked release.
