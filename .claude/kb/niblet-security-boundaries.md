# niblet Security Boundaries

## What is never stored in raw logs
`observe.sh` captures only: `tool_name`, `path` (project-relative), `success` (bool), `phase` (pre/post), `session_id`. Raw `tool_input` and `tool_response` content is deliberately excluded to prevent leaking secrets, API keys, file contents, or command arguments.

## Digest safety
`niblet_write_digest` produces only: `session_id`, `generated_at`, `turns` (int), `failed_commands` (int), `files` (sorted unique path array). Never raw content.

## Path containment
All writes go through `niblet_assert_under_dir` + `niblet_assert_no_symlink_in_path`. A symlink in the path (even if canonically safe) causes demotion to proposal tier. This prevents symlink-chain attacks.

## UPDATE_CLAUDE hardening
`niblet-promote` hard-clamps the `target` for `UPDATE_CLAUDE` actions to `<project-root>/CLAUDE.md` regardless of what the proposal envelope claims, comparing canonical paths to handle macOS `/var` <-> `/private/var` aliasing. A tampered `target: README.md` is caught and warns to stderr.

## Slug validation
`niblet_validate_slug` enforces `^[a-z0-9][a-z0-9._-]*$` (max 64 chars, no `/` or `..`). An invalid slug in any action field causes demotion to proposal with `rejected_reason=invalid-slug:<field>=<value>`.
