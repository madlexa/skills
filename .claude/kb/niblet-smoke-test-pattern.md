# niblet Smoke Test Pattern

## File location
`plugins/niblet/tests/smoke_test.sh`

## What it covers
End-to-end security boundary + lifecycle tests, not unit tests of library functions. Each numbered test corresponds to a contract guarantee:
1. `observe.sh` sanitized capture (no tool content in raw logs)
2. `on_stop.sh` per-session counter
3. `on_prompt_submit.sh` FAST reminder
4. DEEP escalation threshold behaviour
5. `on_session_end.sh` queue entry
6. Cross-session DEEP delivery
7. Safety-net at low threshold
8-9. `niblet-apply` path-traversal rejection -> proposal
10-11. `niblet-apply` auto-write vs proposal routing
12. `niblet-promote` single-frontmatter guarantee for SKILL.md
13. `niblet-promote` APPEND (not replace) for UPDATE_CLAUDE
14. `on_session_start.sh` KB index injection

## Helper pattern
Build hook event JSON via `jq -nc --arg` to avoid shell-quoting issues with secrets in test payloads. Never use `echo '<json>'` for payloads containing single quotes or metacharacters.

## Pass/fail tracking
Use a `FAIL` counter incremented by a `fail()` function; `pass()` prints green. Final `exit $FAIL` lets CI detect failures without `set -e` killing the run mid-test.
