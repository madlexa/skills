# speculator: INDEX sort order must match binary-search order

## The bug (fixed in commit a53bf44)
`index rebuild` sorted INDEX rows with `String.prototype.localeCompare` (no locale arg), which follows the host `LC_COLLATE`. The incremental upsert/remove paths (`document.ts` bsearch*/cmpEdge) read those rows back with **codepoint** binary search (`<` / `>`).

On non-English-collation hosts (Danish, Norwegian, Czech, Estonian, Lithuanian, ...) `localeCompare` orders the slug charset `[a-z0-9-]` differently from codepoint order — e.g. Danish sorts `aa` after `ab`, and hyphen position diverges (`front-end` vs `frontend`). After a rebuild, a remove/upsert binary-searches the wrong slot, fails to find the row, and leaves an orphan index entry pointing at a deleted file (or inserts a duplicate).

## The rule
Any structure that is **sorted once and later read back via binary search** must use the **same comparator** for both. For ASCII slugs use raw codepoint comparison, never `localeCompare`:

```ts
function cmpCodepoint(a: string, b: string): number {
    return a < b ? -1 : a > b ? 1 : 0;
}
```

Applied to both `entityRows.sort` (by `aliases[0]`) and `edgeRows.sort` (by `fromId` then `toId`) in `src/commands/index.ts`.

## Regression test
`tests/index_order_test.sh` (smoke_test.sh section 9): builds a KB with a slug pair that a divergent locale reverses, forces a rebuild under that locale, removes one entity, and asserts no orphan row survives. Skips when no divergent locale is installed on the host.
