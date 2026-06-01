# Changelog

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
