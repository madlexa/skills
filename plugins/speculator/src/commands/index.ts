import {Command} from "commander";
import * as fs from "node:fs";
import * as path from "node:path";
import {Document, type EdgeFrontmatter, type EntityFrontmatter} from "../lib/document";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";
import {errMsg, getOrCreate} from "../lib/command-utils";
import {fmtDate} from "../lib/date-utils";

// Index rows are read back via binary search (document.ts bsearch*/cmpEdge),
// which compares keys with raw codepoint `<`/`>`. The rebuild sort MUST use the
// same ordering — `localeCompare` diverges from codepoint order for slugs with
// variable-position hyphens (e.g. "front-end" vs "frontend"), which would make
// later binary-search lookups miss existing rows and insert duplicates.
function cmpCodepoint(a: string, b: string): number {
    return a < b ? -1 : a > b ? 1 : 0;
}

export const indexRebuildCommand: SpeculatorCommand = {
    name: "index_rebuild",
    description: "Rebuild INDEX files from entity and edge documents",

    type() {
        return defineType({type: "object", properties: {}, required: []});
    },

    register(program: Command): void {
        const index = getOrCreate(program, "index", "Index management commands");

        index
            .command("rebuild")
            .description("Rebuild INDEX files from entity and edge documents")
            .action(async () => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    console.log(await indexRebuildCommand.run({}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run(_args: Record<string, unknown>, dir: string): Promise<string> {
        // Rebuild INDEX.entities.md
        const entitiesDir = path.join(dir, "entities");
        const entityRows: Array<{ id: string; file: string; aliases: string[] }> = [];

        if (fs.existsSync(entitiesDir)) {
            for (const file of fs.readdirSync(entitiesDir).filter((f) => f.endsWith(".md"))) {
                const fm = Document.read<EntityFrontmatter>(path.join(entitiesDir, file)).frontmatter;
                // aliases[0] = slug (canonical), rest = extra aliases
                entityRows.push({
                    id: fm.id,
                    file: `entities/${file}`,
                    aliases: [fm.slug, ...(fm.aliases ?? [])],
                });
            }
        }

        entityRows.sort((a, b) => cmpCodepoint(a.aliases[0] ?? "", b.aliases[0] ?? ""));

        const entityIndex = [
            "# Entity Index",
            "_Sorted by first alias. Auto-generated — do not edit manually. Use `speculator index rebuild`_",
            "",
            "| ID | File | Aliases |",
            "|----|------|---------|",
            ...entityRows.map((r) => `| ${r.id} | ${r.file} | ${r.aliases.join(", ")} |`),
            "",
        ].join("\n");

        fs.writeFileSync(path.join(dir, "INDEX.entities.md"), entityIndex);

        // Rebuild INDEX.edges.md
        const edgesDir = path.join(dir, "edges");
        const edgeRows: Array<{
            fromId: string; toId: string; relation: string;
            id: string; file: string; lastVerified: string;
        }> = [];

        if (fs.existsSync(edgesDir)) {
            for (const file of fs.readdirSync(edgesDir).filter((f) => f.endsWith(".md"))) {
                const fm = Document.read<EdgeFrontmatter>(path.join(edgesDir, file)).frontmatter;
                const [a, b] = [fm["from-id"], fm["to-id"]].sort();
                edgeRows.push({
                    fromId: a, toId: b,
                    relation: fm.relation,
                    id: fm.id,
                    file: `edges/${file}`,
                    lastVerified: fmtDate(fm["last-verified"]),
                });
            }
        }

        edgeRows.sort((a, b) => {
            const cmp = cmpCodepoint(a.fromId, b.fromId);
            return cmp !== 0 ? cmp : cmpCodepoint(a.toId, b.toId);
        });

        const edgeIndex = [
            "# Edge Index",
            "_Sorted by from-id, then to-id. Auto-generated — do not edit manually._",
            "",
            "| From ID | To ID | Relation | UUID | File | Last Verified |",
            "|---------|-------|----------|------|------|--------------|",
            ...edgeRows.map(
                (r) => `| ${r.fromId} | ${r.toId} | ${r.relation} | ${r.id} | ${r.file} | ${r.lastVerified} |`
            ),
            "",
        ].join("\n");

        fs.writeFileSync(path.join(dir, "INDEX.edges.md"), edgeIndex);

        return `Rebuilt INDEX: ${entityRows.length} entities, ${edgeRows.length} edges`;
    },
};
