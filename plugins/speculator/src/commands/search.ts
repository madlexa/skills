import {Command} from "commander";
import * as path from "node:path";
import {Document, type EdgeFrontmatter, type EntityFrontmatter} from "../lib/document";
import {readEdgeIndex, readEntityIndex, uniqueEntities} from "../lib/index-reader";
import {errMsg} from "../lib/command-utils";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";

interface SearchArgs extends Record<string, unknown> {
    query: string;
    metadata?: string; // comma-separated frontmatter fields: slug,id,name,summary,created,tags
    block?: string;    // comma-separated section names to search/show: Code,Human,DB,Params
    any?: boolean;     // match ANY term (OR) instead of all (AND)
}

export const searchCommand: SpeculatorCommand<SearchArgs> = {
    name: "search",
    description: "Search entities and edges by text (summary + all sections)",

    type() {
        return defineType<SearchArgs>({
            type: "object",
            properties: {
                query: {type: "string", description: "Text to search for (space-separated terms are ANDed)"},
                metadata: {
                    type: "string",
                    description: "Comma-separated frontmatter fields to return: slug,id,name,summary,created,tags"
                },
                block: {
                    type: "string",
                    description: "Comma-separated section names to search/show: Code,Human,DB,Params"
                },
                any: {
                    type: "boolean",
                    description: "Match ANY term (OR) instead of requiring all terms (AND)"
                },
            },
            required: ["query"],
        });
    },

    register(program: Command): void {
        program
            .command("search <query>")
            .description("Search entities and edges by text")
            .option("--metadata <fields>", "Comma-separated frontmatter fields to return (e.g. slug,summary)")
            .option("--block <sections>", "Comma-separated sections to search/show (e.g. Code,Human)")
            .option("--any", "Match ANY term (OR) instead of requiring all terms (AND)")
            .action(async (query: string, opts: { metadata?: string; block?: string; any?: boolean }) => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    const result = await searchCommand.run({query, metadata: opts.metadata, block: opts.block, any: opts.any}, dir);
                    if (result) console.log(result);
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({query, metadata, block, any}: SearchArgs, dir: string): Promise<string> {
        const entities = readEntityIndex(dir);
        const edgeRefs = readEdgeIndex(dir);
        const terms = query.trim().split(/\s+/).map((t) => t.toLowerCase()).filter(Boolean);
        const matchesAll = (text: string) => {
            const lower = text.toLowerCase();
            return any
                ? terms.some((t) => lower.includes(t))
                : terms.every((t) => lower.includes(t));
        };

        const metaFields = metadata?.split(",").map((s) => s.trim().toLowerCase());
        const sectionFilter = block?.split(",").map((s) => s.trim().toLowerCase());
        const slugOnly = metaFields?.length === 1 && metaFields[0] === "slug";

        const results: string[] = [];

        for (const ref of uniqueEntities(entities)) {
            const doc = Document.read<EntityFrontmatter>(path.join(dir, ref.file));
            const fm = doc.frontmatter;
            let hit = false;
            const matches: string[] = [];

            // Search summary only when no block filter, or block filter includes "summary"
            const searchSummary = !sectionFilter || sectionFilter.includes("summary");
            if (searchSummary && matchesAll(fm.summary)) {
                hit = true;
                if (!slugOnly && !metaFields) matches.push(`summary: "${fm.summary}"`);
            }

            for (const [section, content] of doc.sections) {
                if (sectionFilter && !sectionFilter.includes(section.toLowerCase())) continue;
                if (matchesAll(content)) {
                    hit = true;
                    if (!slugOnly && !metaFields) {
                        const firstTerm = terms[0];
                        const idx = content.toLowerCase().indexOf(firstTerm);
                        const start = Math.max(0, idx - 40);
                        const fragment = content.slice(start, idx + 60).replace(/\n/g, " ").trim();
                        matches.push(`${section}: ...${fragment}...`);
                    }
                }
            }

            if (hit) {
                if (slugOnly) {
                    results.push(ref.aliases[0]);
                } else if (metaFields) {
                    const parts: string[] = [];
                    for (const field of metaFields) {
                        switch (field) {
                            case "slug":
                                parts.push(ref.aliases[0]);
                                break;
                            case "id":
                                parts.push(fm.id);
                                break;
                            case "name":
                                parts.push(fm.name);
                                break;
                            case "summary":
                                parts.push(fm.summary);
                                break;
                            case "created":
                                parts.push(fm.created);
                                break;
                            case "tags":
                                parts.push((fm.tags ?? []).join(","));
                                break;
                        }
                    }
                    results.push(`[entity] ${parts.join(" | ")}`);
                } else {
                    results.push(`[entity] ${fm.name} (${ref.aliases[0]})`);
                    for (const m of matches) results.push(`  ${m}`);
                    results.push("");
                }
            }
        }

        for (const edgeRef of edgeRefs) {
            const doc = Document.read<EdgeFrontmatter>(path.join(dir, edgeRef.file));
            // Index IDs are canonical-sorted, not directional — read the edge
            // frontmatter for the real semantic from-id/to-id.
            const fromId = doc.frontmatter["from-id"];
            const toId = doc.frontmatter["to-id"];
            const fromRef = entities.get(fromId);
            const toRef = entities.get(toId);
            const fromDisplay = fromRef?.aliases[0] ?? fromId;
            const toDisplay = toRef?.aliases[0] ?? toId;

            for (const [section, content] of doc.sections) {
                if (sectionFilter && !sectionFilter.includes(section.toLowerCase())) continue;
                if (matchesAll(content)) {
                    if (slugOnly) {
                        results.push(`${fromDisplay}--${toDisplay}`);
                    } else if (metaFields) {
                        const parts: string[] = [];
                        for (const f of metaFields) {
                            if (f === "slug") parts.push(`${fromDisplay}--${toDisplay}`);
                            else if (f === "id") parts.push(edgeRef.id);
                            else if (f === "relation") parts.push(edgeRef.relation);
                            else if (f === "created") parts.push(doc.frontmatter.created);
                        }
                        results.push(`[edge] ${parts.join(" | ")}`);
                    } else {
                        const firstTerm = terms[0];
                        const idx = content.toLowerCase().indexOf(firstTerm);
                        const start = Math.max(0, idx - 40);
                        const fragment = content.slice(start, idx + 60).replace(/\n/g, " ").trim();
                        results.push(`[edge] ${fromDisplay} → ${toDisplay} [${edgeRef.relation}]`);
                        results.push(`  ${section}: ...${fragment}...`);
                        results.push("");
                    }
                    break;
                }
            }
        }

        if (results.length === 0) return "";
        return results.join("\n").trimEnd();
    },
};
