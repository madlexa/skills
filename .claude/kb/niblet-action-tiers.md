# niblet Action Tiers

## Auto-write tier (applied immediately, no proposal)
- `ADD_KB_ENTRY` (project scope only)
- `MERGE_KB_ENTRY` (project scope only)
- `UPDATE_KB_ENTRY` (project scope only)
- `DEPRECATE_KB_ENTRY` (project scope only)
- `UPDATE_MEMORY` (project scope only)
- `NOTHING`

## Proposal tier (always staged to `.niblet/proposals/`, never auto-written)
- `CREATE_SKILL`, `UPDATE_SKILL`
- `CREATE_COMMAND`, `UPDATE_COMMAND`
- `CREATE_AGENT`, `UPDATE_AGENT`
- `CREATE_SCRIPT`, `UPDATE_SCRIPT` (also syntax-validated before staging)
- `UPDATE_CLAUDE`
- `OPEN_QUESTION`, `AUDIT_REPORT`
- Any action with `scope: global`

## Promotion path
Proposal files sit in `.niblet/proposals/` until `niblet-promote <file>` is called.
`niblet-promote` is action-aware: it strips the YAML envelope, applies the correct operation (append for UPDATE_CLAUDE, backup+overwrite for UPDATE_*, rename for DEPRECATE_*), then deletes the proposal file on success.
