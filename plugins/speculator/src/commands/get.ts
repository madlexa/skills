import {Command} from "commander";
import * as path from "node:path";
import {Document, type EdgeFrontmatter, type EntityFrontmatter} from "../lib/document";
import {binarySearchEdge, readEdgeIndex, readEntityIndex} from "../lib/index-reader";
import {bfsAllPaths, buildGraph} from "../lib/graph";
import {formatNav} from "../lib/path-formatter";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";
import {fmtDate} from "../lib/date-utils";
import {errMsg, notFoundMsg} from "../lib/command-utils";

interface GetArgs extends Record<string, unknown> {
    slug: string;
    to?: string;
    facet?: string;
    depth?: number;
    verbose?: boolean;
}

export const getCommand: SpeculatorCommand<GetArgs> = {
    name: "get",
    description:
        "Get entity or edge. " +
        "One slug: full entity + connected edges. " +
        "Two slugs: edge doc or BFS path. " +
        "--facet: return only that section. " +
        "--depth N: list reachable entities within N hops.",

    type() {
        return defineType<GetArgs>({
            type: "object",
            properties: {
                slug: {type: "string", description: "Entity slug"},
                to: {type: "string", description: "Target entity slug — triggers edge/path mode"},
                facet: {type: "string", description: "Return only this ## section (e.g. Code, Human)"},
                depth: {type: "number", description: "Max hops for neighborhood listing (enables neighbors mode)"},
                verbose: {type: "boolean", description: "Show first lines of Human section for each connected edge"},
            },
            required: ["slug"],
        });
    },

    register(program: Command): void {
        program
            .command("get <slug> [to]")
            .description("Get entity, edge, path, or neighborhood")
            .option("--facet <name>", "Return only a specific ## section")
            .option("--depth <n>", "Max hops for neighborhood listing", parseInt)
            .option("--verbose", "Show Human section snippet for each connected edge")
            .action(async (slug: string, to: string | undefined, opts: { facet?: string; depth?: number; verbose?: boolean }) => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    console.log(await getCommand.run({slug, to, facet: opts.facet, depth: opts.depth, verbose: opts.verbose}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({slug, to, facet, depth, verbose}: GetArgs, dir: string): Promise<string> {
        const entities = readEntityIndex(dir);
        const fromEntity = entities.get(slug);
        if (!fromEntity) throw new Error(notFoundMsg(slug, entities));

        // --- Neighbors mode (--depth) ---
        if (depth != null) {
            const edgeRefs = readEdgeIndex(dir);
            const graph = buildGraph(edgeRefs);
            const rows: Array<{ d: number; slug: string; name: string; summary: string; via: string }> = [];
            const visited = new Set<string>([fromEntity.id]);
            const queue: Array<[string, number, string[]]> = [[fromEntity.id, 0, []]];

            while (queue.length > 0) {
                const [currentId, currentDepth, viaParts] = queue.shift()!;
                if (currentDepth >= depth) continue;
                for (const neighbor of graph.get(currentId) ?? []) {
                    if (visited.has(neighbor.targetId)) continue;
                    visited.add(neighbor.targetId);
                    const ref = entities.get(neighbor.targetId);
                    if (!ref) continue;
                    const doc = Document.read<EntityFrontmatter>(path.join(dir, ref.file));
                    const newVia = [...viaParts, neighbor.relation];
                    rows.push({
                        d: currentDepth + 1,
                        slug: ref.aliases[0],
                        name: doc.frontmatter.name,
                        summary: doc.frontmatter.summary,
                        via: newVia.join(" → ")
                    });
                    queue.push([neighbor.targetId, currentDepth + 1, newVia]);
                }
            }

            if (rows.length === 0) return `No neighbors found for: ${slug}`;
            const lines = ["Depth | Slug | Name | Summary | Via", "------|------|------|---------|----"];
            for (const r of rows) lines.push(`${r.d} | ${r.slug} | ${r.name} | ${r.summary} | ${r.via}`);
            return lines.join("\n");
        }

        // --- Two-slug mode: edge or path ---
        if (to) {
            const toEntity = entities.get(to);
            if (!toEntity) throw new Error(`'${to}' not found. Use list_entities() to find the correct slug.`);

            const edgeRefs = readEdgeIndex(dir);
            const [smallerId, largerId] = [fromEntity.id, toEntity.id].sort();
            const directEdge = binarySearchEdge(edgeRefs, smallerId, largerId);

            if (directEdge) {
                const doc = Document.read<EdgeFrontmatter>(path.join(dir, directEdge.file));

                if (facet) {
                    const section = doc.getSection(facet);
                    if (!section) throw new Error(`Section '${facet}' not found on edge ${slug}→${to}. Call get('${slug}', '${to}') without facet to see available sections.`);
                    return `## ${facet}\n${section}`;
                }

                const fm = doc.frontmatter;
                const fromDisplay = fromEntity.aliases[0] ?? slug;
                const toDisplay = toEntity.aliases[0] ?? to;
                const lines = [
                    `# ${fromDisplay} ↔ ${toDisplay} [${fm.relation}]`,
                    `ID: ${fm.id}`,
                    `Created: ${fmtDate(fm.created)}`,
                    `Last verified: ${fmtDate(fm["last-verified"])}`,
                    "",
                ];
                for (const [heading, body] of doc.sections) {
                    lines.push(`## ${heading}`, body, "");
                }
                return lines.join("\n");
            }

            // BFS path
            const allPaths = bfsAllPaths(buildGraph(edgeRefs), fromEntity.id, toEntity.id);
            if (allPaths.length === 0) throw new Error(`No connection between '${slug}' and '${to}'. Use get('${slug}', depth=2) to see neighbors, or add_edge() to create a link.`);

            if (allPaths.length === 1) return formatNav(allPaths[0], entities, dir);

            // Multiple paths
            const fromDisplay = fromEntity.aliases[0] ?? slug;
            const toDisplay = toEntity.aliases[0] ?? to;
            const lines = [`=== ${allPaths.length} paths: ${fromDisplay} ↔ ${toDisplay} ===`, ""];
            for (let i = 0; i < allPaths.length; i++) {
                const steps = allPaths[i];
                const parts = [fromDisplay];
                for (const step of steps) {
                    const ref = entities.get(step.toId);
                    parts.push(`--[${step.relation}]-->`, ref?.aliases[0] ?? step.toId);
                }
                lines.push(`[${i + 1}] ${parts.join(" ")}`);
                const hops = [slug, ...steps.map((s) => entities.get(s.toId)?.aliases[0] ?? s.toId)];
                lines.push(`    → ${hops.slice(0, -1).map((h, j) => `speculator get ${h} ${hops[j + 1]}`).join(" && ")}`);
                lines.push("");
            }
            return lines.join("\n");
        }

        // --- Single-slug mode: entity ---
        const doc = Document.read<EntityFrontmatter>(path.join(dir, fromEntity.file));

        if (facet) {
            const section = doc.getSection(facet);
            if (!section) throw new Error(`Section '${facet}' not found on entity '${slug}'. Call get('${slug}') without facet to see available sections.`);
            return `## ${facet}\n${section}`;
        }

        const fm = doc.frontmatter;
        const lines = [
            `# ${fm.name}`,
            `ID: ${fm.id}`,
            `Summary: ${fm.summary}`,
            `Tags: ${fm.tags?.join(", ") ?? ""}`,
            "",
        ];
        for (const [heading, body] of doc.sections) {
            lines.push(`## ${heading}`, body, "");
        }

        const edgeRefs = readEdgeIndex(dir);
        const connected = edgeRefs.filter((e) => e.fromId === fromEntity.id || e.toId === fromEntity.id);
        if (connected.length > 0) {
            lines.push("---", "## Edges", "");
            for (const e of connected) {
                const otherId = e.fromId === fromEntity.id ? e.toId : e.fromId;
                const otherRef = entities.get(otherId);
                const otherDisplay = otherRef?.aliases[0] ?? otherId;
                const dir_ = `↔ ${otherDisplay}`;
                lines.push(`- ${dir_} [${e.relation}] (verified: ${e.lastVerified})`);
                if (verbose) {
                    const human = Document.read<EdgeFrontmatter>(path.join(dir, e.file)).getSection("Human");
                    if (human) {
                        const snippet = human.split("\n").filter(l => l.trim()).slice(0, 3).map(l => `  ${l}`).join("\n");
                        if (snippet) lines.push(snippet);
                    }
                }
            }
        }
        return lines.join("\n");
    },
};
