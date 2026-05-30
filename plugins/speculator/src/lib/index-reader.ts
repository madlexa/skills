import * as fs from "node:fs";
import * as path from "node:path";
import {Document, type EdgeFrontmatter} from "./document";

export interface EntityRef {
    id: string;
    file: string;
    aliases: string[]; // first = canonical display key (slug)
}

export interface EdgeRef {
    fromId: string;
    toId: string;
    relation: string;
    id: string;
    file: string;
    lastVerified: string;
}

function parseMarkdownTable(content: string): string[][] {
    const lines = content.split("\n");
    const rows: string[][] = [];

    for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith("|")) continue;
        // Skip separator row (|---|---|...)
        if (/^\|[\s-|]+\|$/.test(trimmed)) continue;
        const cells = trimmed
            .split("|")
            .slice(1, -1)
            .map((c) => c.trim());
        rows.push(cells);
    }

    // First row is header, rest are data
    return rows.slice(1);
}

export function readEntityIndex(dir: string): Map<string, EntityRef> {
    const indexPath = path.join(dir, "INDEX.entities.md");
    if (!fs.existsSync(indexPath)) {
        return new Map();
    }
    const content = fs.readFileSync(indexPath, "utf-8");
    const rows = parseMarkdownTable(content);
    const entities = new Map<string, EntityRef>();

    for (const row of rows) {
        if (row.length < 2) continue;
        const [id, file] = row;
        const aliasesRaw = row[2] ?? "";
        const aliases = aliasesRaw ? aliasesRaw.split(",").map((a) => a.trim()).filter(Boolean) : [];
        const ref: EntityRef = {id, file, aliases};
        // Map by id and by each alias
        entities.set(id, ref);
        for (const alias of aliases) {
            entities.set(alias, ref);
        }
    }

    return entities;
}

/** Returns unique EntityRef objects (deduplicated by id). */
export function uniqueEntities(entities: Map<string, EntityRef>): EntityRef[] {
    const seen = new Set<string>();
    const result: EntityRef[] = [];
    for (const ref of entities.values()) {
        if (!seen.has(ref.id)) {
            seen.add(ref.id);
            result.push(ref);
        }
    }
    return result;
}

export function readEdgeIndex(dir: string): EdgeRef[] {
    const indexPath = path.join(dir, "INDEX.edges.md");
    if (!fs.existsSync(indexPath)) {
        return [];
    }
    const content = fs.readFileSync(indexPath, "utf-8");
    const rows = parseMarkdownTable(content);
    const edges: EdgeRef[] = [];

    for (const row of rows) {
        if (row.length < 6) continue;
        const [fromId, toId, relation, id, file, lastVerified] = row;
        edges.push({fromId, toId, relation, id, file, lastVerified});
    }

    return edges;
}

/**
 * Index rows store from-id/to-id in canonical (sorted) order, not semantic
 * order. To render directional endpoints correctly, read each edge file's
 * frontmatter for the real semantic from-id/to-id, then resolve to display slugs.
 */
export function semanticEndpoints(
    e: EdgeRef,
    dir: string,
    entities: Map<string, EntityRef>,
): { fromDisplay: string; toDisplay: string } {
    const fm = Document.read<EdgeFrontmatter>(path.join(dir, e.file)).frontmatter;
    const fromId = fm["from-id"];
    const toId = fm["to-id"];
    const fromRef = entities.get(fromId);
    const toRef = entities.get(toId);
    return {
        fromDisplay: fromRef ? (fromRef.aliases[0] ?? fromId) : fromId,
        toDisplay: toRef ? (toRef.aliases[0] ?? toId) : toId,
    };
}

/** Binary search on a sorted EdgeRef[] by (fromId, toId). */
export function binarySearchEdge(edges: EdgeRef[], fromId: string, toId: string): EdgeRef | undefined {
    let lo = 0, hi = edges.length - 1;
    while (lo <= hi) {
        const mid = (lo + hi) >>> 1;
        const e = edges[mid];
        const cmp = e.fromId < fromId ? -1 : e.fromId > fromId ? 1 : e.toId < toId ? -1 : e.toId > toId ? 1 : 0;
        if (cmp === 0) return e;
        if (cmp < 0) lo = mid + 1; else hi = mid - 1;
    }
    return undefined;
}

export interface ResolvedEdge {
    fromEntity: EntityRef;
    toEntity: EntityRef;
    edgeRef: EdgeRef;
}

export function resolveEdge(dir: string, from: string, to: string): ResolvedEdge {
    const entities = readEntityIndex(dir);
    const fromEntity = entities.get(from);
    const toEntity = entities.get(to);
    if (!fromEntity) throw new Error(`'${from}' not found. Use list_entities() to find the correct slug.`);
    if (!toEntity) throw new Error(`'${to}' not found. Use list_entities() to find the correct slug.`);

    const [a, b] = [fromEntity.id, toEntity.id].sort();
    const edgeRef = binarySearchEdge(readEdgeIndex(dir), a, b);
    if (!edgeRef) throw new Error(`No edge between '${from}' and '${to}'. Use list_edges() to verify, or add_edge() to create one.`);

    return {fromEntity, toEntity, edgeRef};
}
