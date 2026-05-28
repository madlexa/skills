# niblet Concurrency Hardening Patterns

Patterns applied in the v0.3.x hardening pass to make niblet store writes race-safe.

## TOCTOU-safe file naming (write_proposal, audit queue)

Previous pattern used a `while [ -e "$path" ]` loop then wrote directly —
a second concurrent process could claim the same name in the window between
the check and the write.

New pattern: write to a `mktemp` temp file first, then atomically claim a
slot with `ln` (hard-link):

```sh
_tmp="$(mktemp "$dir/XXXXXXXX.tmp" 2>/dev/null)" || _tmp="$dir/.tmp-$$-$(ts)"
# ... write content to $_tmp ...
while [ "$_mv_tries" -lt 50 ]; do
  if ln "$_tmp" "$target_path" 2>/dev/null; then
    rm -f "$_tmp"
    break
  fi
  target_path="${base}-$((i++)}.md"
done
```

`ln` uses `link()` which is POSIX-atomic and fails with EEXIST if the slot
is already taken. Works because both paths are on the same filesystem.
`mv -n` is not portable for this on BSD/macOS.

## session_count advisory lock (on_session_end.sh)

Previous code had an unguarded read-modify-write on `session_count`.

New pattern: use `mkdir` as a portable advisory lock (atomic on POSIX),
with up to 3 retry attempts (1 s sleep each):

```sh
_sclock="${SESSION_COUNT_FILE}.lck"
_sclock_held=0
_sc_attempts=3
while [ "$_sc_attempts" -gt 0 ]; do
  if mkdir "$_sclock" 2>/dev/null; then _sclock_held=1; break; fi
  _sc_attempts=$((_sc_attempts - 1))
  [ "$_sc_attempts" -gt 0 ] && sleep 1
done
# ... read, increment, write ...
[ "$_sclock_held" = "1" ] && rmdir "$_sclock"
```

The audit-queue trigger is gated on `_sclock_held=1` so duplicate audit
entries are impossible when two sessions end at the same timestamp.

## niblet-status awk envelope parser fix

The action-type breakdown `awk` in `niblet-status` previously maintained
a per-file `e` counter that was not reset between files (`awk` with glob
expansion reads multiple files in one pass). Fixed with `FNR==1{e=0}`:

```sh
awk 'FNR==1{e=0} /^---$/{e++; next} e==1 && /^action:/{print $2; e=2}' \
  "$PROPOSALS_DIR"/*.md
```

Without `FNR==1{e=0}` the counter carries over across files, causing action
types of later proposals to be silently missed.

## Beginner-summary marker injection guard

When `NIBLET_BEGINNER_UX=1` a human-readable `<!-- NIBLET BEGINNER SUMMARY -->`
block is written into the proposal. A malicious payload containing the end-
marker string `<!-- END NIBLET BEGINNER SUMMARY -->` could close the block
early and have injected text promoted as artifact content.

Fix: strip both marker strings from the summary content before embedding:

```sh
_safe_bsum="$(printf '%s' "$BEGINNER_SUMMARY" \
  | grep -vF '<!-- NIBLET BEGINNER SUMMARY -->' \
  | grep -vF '<!-- END NIBLET BEGINNER SUMMARY -->' \
  || true)"
```

The envelope also gains `has_beginner_summary: true` so `extract_payload`
in `niblet-promote` can strip the block cleanly without corrupting legitimate
artifacts that happen to contain those marker strings.

## UPDATE_SCRIPT syntax validation before staging

`niblet-apply` now syntax-validates `UPDATE_SCRIPT` payloads (same as
`CREATE_SCRIPT`) before staging as a proposal, recording the result in
`validation_details`. `niblet-promote` re-validates on promotion and refuses
with exit 65 if the script no longer passes `bash -n` / `python3 -m py_compile`.

## UPDATE_SCRIPT in niblet-promote

`UPDATE_SCRIPT` was previously handled by the same branch as
`UPDATE_SKILL/UPDATE_AGENT/UPDATE_COMMAND`, which wrote the payload without
syntax checking and left any executable bit intact. It is now a separate
branch with validation + `chmod a-x`, matching the `CREATE_SCRIPT` safety model.
