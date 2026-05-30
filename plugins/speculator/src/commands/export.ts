import {Command} from "commander";
import * as path from "node:path";
import {Document, type EntityFrontmatter} from "../lib/document";
import {readEdgeIndex, readEntityIndex, semanticEndpoints, uniqueEntities} from "../lib/index-reader";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";
import {errMsg} from "../lib/command-utils";

type ExportFormat = "mermaid" | "dot" | "json";

interface ExportArgs extends Record<string, unknown> {
    format: ExportFormat;
}

export const exportCommand: SpeculatorCommand<ExportArgs> = {
    name: "export",
    description: "Export the knowledge graph (format: mermaid | dot | json)",

    type() {
        return defineType<ExportArgs>({
            type: "object",
            properties: {
                format: {
                    type: "string",
                    description: "Output format: mermaid, dot, json",
                },
            },
            required: ["format"],
        });
    },

    register(program: Command): void {
        program
            .command("export <format>")
            .description("Export knowledge graph (mermaid|dot|json)")
            .action(async (format: string) => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    if (format !== "mermaid" && format !== "dot" && format !== "json") {
                        throw new Error(`Unknown format '${format}'. Supported formats: json, mermaid, dot.`);
                    }
                    console.log(await exportCommand.run({format: format as ExportFormat}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({format}: ExportArgs, dir: string): Promise<string> {
        const entities = readEntityIndex(dir);
        const edgeRefs = readEdgeIndex(dir);
        const unique = uniqueEntities(entities);

        if (format === "mermaid") {
            const lines = ["flowchart LR"];
            for (const e of unique) {
                const fm = Document.read<EntityFrontmatter>(path.join(dir, e.file)).frontmatter;
                const id = (e.aliases[0] ?? e.id).replace(/[^a-zA-Z0-9]/g, "_");
                lines.push(`  ${id}["${fm.name}"]`);
            }
            lines.push("");
            for (const edge of edgeRefs) {
                const {fromDisplay, toDisplay} = semanticEndpoints(edge, dir, entities);
                const fromId = fromDisplay.replace(/[^a-zA-Z0-9]/g, "_");
                const toId = toDisplay.replace(/[^a-zA-Z0-9]/g, "_");
                lines.push(`  ${fromId} -- "${edge.relation}" --> ${toId}`);
            }
            return lines.join("\n");
        }

        if (format === "dot") {
            const lines = ["digraph G {", "  rankdir=LR;", ""];
            for (const e of unique) {
                const fm = Document.read<EntityFrontmatter>(path.join(dir, e.file)).frontmatter;
                const slug = e.aliases[0] ?? e.id;
                lines.push(`  "${slug}" [label="${fm.name}"];`);
            }
            lines.push("");
            for (const edge of edgeRefs) {
                const {fromDisplay, toDisplay} = semanticEndpoints(edge, dir, entities);
                lines.push(`  "${fromDisplay}" -> "${toDisplay}" [label="${edge.relation}"];`);
            }
            lines.push("}");
            return lines.join("\n");
        }

        // json
        const entityList = unique.map((e) => {
            const fm = Document.read<EntityFrontmatter>(path.join(dir, e.file)).frontmatter;
            return {
                id: e.id,
                slug: e.aliases[0] ?? e.id,
                name: fm.name,
                summary: fm.summary,
                aliases: e.aliases,
            };
        });
        const edgeList = edgeRefs.map((e) => {
            const {fromDisplay, toDisplay} = semanticEndpoints(e, dir, entities);
            return {
                id: e.id,
                from: fromDisplay,
                to: toDisplay,
                relation: e.relation,
                lastVerified: e.lastVerified,
            };
        });
        return JSON.stringify({entities: entityList, edges: edgeList}, null, 2);
    },
};
