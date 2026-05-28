# niblet Store Layout

All per-project niblet state lives under `<project-root>/.niblet/`:

```
.niblet/
  raw/                  # sanitized JSONL session logs (tool name + path + exit only)
  digests/              # per-session JSON summaries (turns, failed_commands, files[])
  sessions/<id>/
    task_counter        # turn count for this session
  pending_deep/         # queue files for cross-session DEEP checkpoint delivery
  index/                # (reserved)
  distill_queue/        # (reserved)
  audit_queue/          # (reserved)
  session_count         # project-wide integer counter of ended sessions
  proposals/            # staged actions awaiting niblet-promote
  inbox/                # niblet-deep output JSON files (temporary)
```

Key design constraint: per-session markers (e.g. `sessions/<id>/marker`) are NOT used for cross-session delivery because `UserPromptSubmit` only sees its own `session_id`. The `pending_deep/` queue + `on_session_end.sh` is the canonical pattern for cross-session signalling.
