import {Command} from "commander";
import * as fs from "node:fs";
import * as path from "node:path";
import {Document, type EdgeFrontmatter, type EntityFrontmatter} from "../lib/document";
import {readEdgeIndex, readEntityIndex, semanticEndpoints, uniqueEntities} from "../lib/index-reader";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";
import {errMsg, getOrCreate, notFoundMsg} from "../lib/command-utils";

interface ListEntitiesArgs extends Record<string, unknown> {
    tag?: string;
}

interface ListEdgesArgs extends Record<string, unknown> {
    from?: string;
    to?: string;
    days?: number;
    staleRelative?: boolean;
}

export const listEntitiesCommand: SpeculatorCommand<ListEntitiesArgs> = {
    name: "list_entities",
    description: "List all entities from the index",

    type() {
        return defineType<ListEntitiesArgs>({
            type: "object",
            properties: {
                tag: {type: "string", description: "Filter by tag (optional)"},
            },
            required: [],
        });
    },

    register(program: Command): void {
        const list = getOrCreate(program, "list", "List entities or edges");

        list
            .command("entities")
            .description("List all entities from INDEX")
            .option("--tag <tag>", "Filter entities by tag")
            .action(async (opts: ListEntitiesArgs) => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    console.log(await listEntitiesCommand.run({tag: opts.tag}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({tag}: ListEntitiesArgs, dir: string): Promise<string> {
        const entities = readEntityIndex(dir);
        const unique = uniqueEntities(entities);
        if (unique.length === 0) return "No entities found.";

        const rows: { name: string; slug: string; summary: string }[] = [];
        for (const ref of unique) {
            const fm = Document.read<EntityFrontmatter>(path.join(dir, ref.file)).frontmatter;
            if (tag && !fm.tags?.includes(tag)) continue;
            rows.push({name: fm.name, slug: fm.slug, summary: fm.summary});
        }

        if (rows.length === 0) return tag ? `No entities with tag: ${tag}` : "No entities found.";
        rows.sort((a, b) => a.name.localeCompare(b.name));

        const lines = ["Name | Slug | Summary", "-----|------|--------"];
        for (const r of rows) {
            lines.push(`${r.name} | ${r.slug} | ${r.summary}`);
        }
        return lines.join("\n");
    },
};

export const listEdgesCommand: SpeculatorCommand<ListEdgesArgs> = {
    name: "list_edges",
    description: "List all edges from the index, optionally filtered by from slug",

    type() {
        return defineType<ListEdgesArgs>({
            type: "object",
            properties: {
                from: {type: "string", description: "Filter edges involving this entity (both directions)"},
                to: {type: "string", description: "Filter edges where this entity is the target (incoming edges only)"},
                days: {type: "number", description: "Show only edges not verified in the last N days (stale filter)"},
                staleRelative: {type: "boolean", description: "Show edges whose last-verified predates an adjacent entity's file mtime"},
            },
            required: [],
        });
    },

    register(program: Command): void {
        const list = getOrCreate(program, "list", "List entities or edges");

        list
            .command("edges")
            .description("List all edges from INDEX")
            .option("--from <slug>", "Filter edges involving this entity (both directions)")
            .option("--to <slug>", "Filter edges where this entity is the target (incoming only)")
            .option("--stale <days>", "Show only edges not verified in the last N days", parseInt)
            .option("--stale-relative", "Show edges whose last-verified predates an adjacent entity's file mtime")
            .action(async (opts: { from?: string; to?: string; stale?: number; staleRelative?: boolean }) => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    console.log(await listEdgesCommand.run({from: opts.from, to: opts.to, days: opts.stale, staleRelative: opts.staleRelative}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({from: fromFilter, to: toFilter, days, staleRelative}: ListEdgesArgs, dir: string): Promise<string> {
        const entities = readEntityIndex(dir);
        let edges = readEdgeIndex(dir);

        if (fromFilter) {
            const fromEntity = entities.get(fromFilter);
            if (!fromEntity) throw new Error(notFoundMsg(fromFilter, entities));
            edges = edges.filter((e) => e.fromId === fromEntity.id || e.toId === fromEntity.id);
        }

        if (toFilter) {
            const toEntity = entities.get(toFilter);
            if (!toEntity) throw new Error(notFoundMsg(toFilter, entities));
            // IDs in the index are stored in sorted (canonical) order, so we must
            // read each edge file to find the actual semantic "to-id".
            const involving = edges.filter((e) => e.fromId === toEntity.id || e.toId === toEntity.id);
            edges = involving.filter((e) => {
                const doc = Document.read<EdgeFrontmatter>(path.join(dir, e.file));
                return doc.frontmatter["to-id"] === toEntity.id;
            });
        }

        if (days !== undefined && days > 0) {
            const cutoff = Date.now() - days * 86400000;
            edges = edges.filter((e) => {
                if (!e.lastVerified) return true;
                return new Date(e.lastVerified).getTime() < cutoff;
            });
        }

        if (staleRelative) {
            edges = edges.filter((e) => {
                const fromRef = entities.get(e.fromId);
                const toRef = entities.get(e.toId);
                if (!fromRef || !toRef) return false;
                const entityMaxMtime = Math.max(
                    fs.statSync(path.join(dir, fromRef.file)).mtimeMs,
                    fs.statSync(path.join(dir, toRef.file)).mtimeMs,
                );
                const edgeMtime = fs.statSync(path.join(dir, e.file)).mtimeMs;
                return entityMaxMtime > edgeMtime;
            });
        }

        if (edges.length === 0) return "No edges found.";

        if (staleRelative) {
            const lines = ["From | To | Relation | Last Verified | Entity updated", "-----|-----|----------|---------------|---------------"];
            for (const e of edges) {
                const {fromDisplay, toDisplay} = semanticEndpoints(e, dir, entities);
                // mtime span is symmetric across the two endpoints, so canonical ids are fine here.
                const fromRef = entities.get(e.fromId);
                const toRef = entities.get(e.toId);
                const fromMtime = fromRef ? fs.statSync(path.join(dir, fromRef.file)).mtimeMs : 0;
                const toMtime = toRef ? fs.statSync(path.join(dir, toRef.file)).mtimeMs : 0;
                const entityUpdated = new Date(Math.max(fromMtime, toMtime)).toISOString().slice(0, 10);
                lines.push(`${fromDisplay} | ${toDisplay} | ${e.relation} | ${e.lastVerified} | ${entityUpdated}`);
            }
            return lines.join("\n");
        }

        const lines = ["From | To | Relation | Last Verified", "-----|-----|----------|---------------"];
        for (const e of edges) {
            const {fromDisplay, toDisplay} = semanticEndpoints(e, dir, entities);
            lines.push(`${fromDisplay} | ${toDisplay} | ${e.relation} | ${e.lastVerified}`);
        }
        return lines.join("\n");
    },
};
