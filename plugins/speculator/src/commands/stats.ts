import {Command} from "commander";
import * as path from "node:path";
import {Document, type EntityFrontmatter} from "../lib/document";
import {readEdgeIndex, readEntityIndex, uniqueEntities} from "../lib/index-reader";
import {errMsg} from "../lib/command-utils";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";

export const statsCommand: SpeculatorCommand = {
    name: "stats",
    description: "Show knowledge base statistics: entity/edge counts, orphans, top connected, stale edges",

    type() {
        return defineType({type: "object", properties: {}, required: []});
    },

    register(program: Command): void {
        program
            .command("stats")
            .description("Show KB statistics")
            .action(async () => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    console.log(await statsCommand.run({}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run(_args: Record<string, unknown>, dir: string): Promise<string> {
        const entities = readEntityIndex(dir);
        const edgeRefs = readEdgeIndex(dir);
        const unique = uniqueEntities(entities);

        const edgeCount = new Map<string, number>();
        for (const e of edgeRefs) {
            edgeCount.set(e.fromId, (edgeCount.get(e.fromId) ?? 0) + 1);
            edgeCount.set(e.toId, (edgeCount.get(e.toId) ?? 0) + 1);
        }

        const orphans = unique.filter((e) => !edgeCount.has(e.id));

        const topConnected = [...unique]
            .filter((e) => edgeCount.has(e.id))
            .sort((a, b) => (edgeCount.get(b.id) ?? 0) - (edgeCount.get(a.id) ?? 0))
            .slice(0, 5);

        const now = Date.now();
        const stale30 = edgeRefs.filter((e) => {
            if (!e.lastVerified) return true;
            return (now - new Date(e.lastVerified).getTime()) / 86400000 > 30;
        });

        const avgEdges =
            unique.length > 0 ? ((edgeRefs.length * 2) / unique.length).toFixed(1) : "0.0";

        const lines = [
            `Entities:     ${unique.length}`,
            `Edges:        ${edgeRefs.length}`,
            `Orphans:      ${orphans.length}`,
            `Avg edges:    ${avgEdges}`,
            `Stale (>30d): ${stale30.length}`,
        ];

        if (topConnected.length > 0) {
            lines.push("", "Top connected:");
            for (const e of topConnected) {
                const label = (e.aliases[0] ?? e.id).padEnd(24);
                lines.push(`  ${label} ${edgeCount.get(e.id)} edges`);
            }
        }

        if (orphans.length > 0) {
            lines.push("", "Orphan entities:");
            for (const e of orphans) {
                const fm = Document.read<EntityFrontmatter>(path.join(dir, e.file)).frontmatter;
                lines.push(`  ${e.aliases[0] ?? e.id} — ${fm.summary}`);
            }
        }

        return lines.join("\n");
    },
};
