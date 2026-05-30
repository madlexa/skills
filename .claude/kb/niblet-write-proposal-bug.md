<!-- DEPRECATED 2026-05-30T10:12:07Z -->
# niblet-apply: write_proposal loses REASON and EVIDENCE

## Bug
write_proposal() accepts a local parameter $reason (used only for rejected_reason: in containment failures). For normal proposal calls the parameter is always empty, so the global $REASON variable (parsed from the agent JSON action) is silently dropped.

EVIDENCE was never declared or parsed at all.

## Root cause (niblet-apply ~line 72, ~line 141)
- Parse block (~line 78) never extracts EVIDENCE
- write_proposal() checks local param $reason, not global $REASON

## Fix (plan: docs/plans/2026-05-28-niblet-fix-version-and-proposal-fields.md)
1. Add EVIDENCE parse from jq to parse block
2. In write_proposal(), emit reason: when $REASON is non-empty
3. Emit evidence: when $EVIDENCE is non-empty
4. Add smoke test #52 to verify round-trip

## Also
marketplace.json (root .claude-plugin/marketplace.json line 12) still says v0.2.0 while plugin.json and README say v0.3.0.
