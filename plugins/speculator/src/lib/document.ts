import * as fs from "node:fs";
import * as path from "node:path";
import {parse as yamlParse, stringify} from "yaml";
import {fmtDate} from "./date-utils";

export function matter(text: string): { data: Record<string, unknown>; content: string } {
    const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
    if (!match) return {data: {}, content: text};
    const data = (yamlParse(match[1]) as Record<string, unknown>) ?? {};
    return {data, content: match[2]};
}

export interface EntityFrontmatter {
    id: string;
    type: "entity";
    name: string;
    slug: string;
    summary: string;
    tags: string[];
    created: string;
    aliases?: string[];
}

export interface EdgeFrontmatter {
    id: string;
    type: "edge";
    "from-id": string;
    "to-id": string;
    relation: string;
    created: string;
    "last-verified": string | Date;
    deprecated?: string;
    // Legacy fields (may exist in old files, ignored for logic)
    name?: string;
    slug?: string;
    "from-name"?: string;
    "to-name"?: string;
}

export function serialize(fm: object): string {
    return `---\n${stringify(fm).trimEnd()}\n---`;
}

function parseSections(content: string): Map<string, string> {
    const sections = new Map<string, string>();
    const lines = content.split("\n");
    let currentSection: string | null = null;
    let currentLines: string[] = [];

    for (const line of lines) {
        const match = line.match(/^## (.+)$/);
        if (match) {
            if (currentSection !== null) {
                sections.set(currentSection, currentLines.join("\n").trim());
            }
            currentSection = match[1];
            currentLines = [];
        } else if (currentSection !== null) {
            currentLines.push(line);
        }
    }

    if (currentSection !== null) {
        sections.set(currentSection, currentLines.join("\n").trim());
    }

    return sections;
}

export class Document<T extends EntityFrontmatter | EdgeFrontmatter> {
    constructor(
        public readonly frontmatter: T,
        public readonly content: string,
        public readonly sections: Map<string, string>
    ) {
    }

    static read<T extends EntityFrontmatter | EdgeFrontmatter>(filePath: string): Document<T> {
        const raw = fs.readFileSync(filePath, "utf-8");
        const {data, content} = matter(raw);
        const fm = data as T;
        // Normalize YAML-parsed Date objects back to ISO strings
        const lv = (fm as EdgeFrontmatter)["last-verified"];
        if (lv instanceof Date) {
            (fm as EdgeFrontmatter)["last-verified"] = fmtDate(lv);
        }
        return new Document<T>(fm, content, parseSections(content));
    }

    static entity(fm: EntityFrontmatter): Document<EntityFrontmatter> {
        return new Document(fm, "", new Map([["Human", fm.summary]]));
    }

    static edge(fm: EdgeFrontmatter): Document<EdgeFrontmatter> {
        return new Document(fm, "", new Map([["Human", ""]]));
    }

    getSection(name: string): string | undefined {
        for (const [key, value] of this.sections) {
            if (key.toLowerCase() === name.toLowerCase()) return value;
        }
        return undefined;
    }

    write(dir: string, fromDisplay?: string, toDisplay?: string): void {
        const fm = this.frontmatter;
        let filePath: string;
        let title: string;

        if (fm.type === "entity") {
            const e = fm as EntityFrontmatter;
            filePath = path.join(dir, "entities", `${e.slug}.md`);
            title = `# ${e.name}`;
        } else {
            const e = fm as EdgeFrontmatter;
            const slug = e.slug ?? `${e["from-id"]}--${e.relation}--${e["to-id"]}`;
            filePath = path.join(dir, "edges", `${slug}.md`);
            title = fromDisplay && toDisplay
                ? `# ${fromDisplay} → ${toDisplay} [${e.relation}]`
                : `# edge [${e.relation}]`;
        }

        const body: string[] = [serialize(fm), "", title, ""];
        for (const [heading, content] of this.sections) {
            body.push(`## ${heading}`, content, "");
        }
        fs.writeFileSync(filePath, body.join("\n"));
    }
}

// --- Index helpers ---

const ENTITY_INDEX_DEFAULT = `# Entity Index
_Sorted by first alias. Auto-generated — do not edit manually. Use \`speculator index rebuild\`_

| ID | File | Aliases |
|----|------|---------|
`;

const EDGE_INDEX_DEFAULT = `# Edge Index
_Sorted by from-id, then to-id. Auto-generated — do not edit manually._

| From ID | To ID | Relation | UUID | File | Last Verified |
|---------|-------|----------|------|------|--------------|
`;

function readIndexTable(indexPath: string, defaultContent: string): { headerLines: string[]; dataRows: string[] } {
    const content = fs.existsSync(indexPath) ? fs.readFileSync(indexPath, "utf-8") : defaultContent;
    const headerLines: string[] = [];
    const dataRows: string[] = [];
    let headerDone = false;
    for (const line of content.split("\n")) {
        const t = line.trim();
        if (/^\|[\s-|]+\|$/.test(t)) {
            headerDone = true;
            headerLines.push(line);
        } else if (t.startsWith("|")) {
            (headerDone ? dataRows : headerLines).push(t);
        } else if (!headerDone) {
            headerLines.push(line);
        }
    }
    return {headerLines, dataRows};
}

function writeIndexTable(indexPath: string, headerLines: string[], dataRows: string[]): void {
    fs.writeFileSync(indexPath, [...headerLines, ...dataRows, ""].join("\n"));
}

// Entity rows: | ID | File | Aliases | — sorted by aliases[0] (col 3)
function entitySortKey(row: string): string {
    return (row.split("|")[3] ?? "").trim().split(",")[0]?.trim() ?? "";
}

function bsearchInsertEntity(rows: string[], alias: string): number {
    let lo = 0, hi = rows.length;
    while (lo < hi) {
        const mid = (lo + hi) >>> 1;
        if (entitySortKey(rows[mid]) < alias) lo = mid + 1; else hi = mid;
    }
    return lo;
}

function bsearchFindEntity(rows: string[], alias: string): number {
    let lo = 0, hi = rows.length - 1;
    while (lo <= hi) {
        const mid = (lo + hi) >>> 1;
        const k = entitySortKey(rows[mid]);
        if (k === alias) return mid;
        if (k < alias) lo = mid + 1; else hi = mid - 1;
    }
    return -1;
}

// Edge rows: | From ID | To ID | ... | — sorted by (fromId, toId) (cols 1, 2)
function edgeSortKey(row: string): [string, string] {
    const c = row.split("|").map((s) => s.trim());
    return [c[1] ?? "", c[2] ?? ""];
}

function cmpEdge([af, at]: [string, string], fromId: string, toId: string): number {
    return af < fromId ? -1 : af > fromId ? 1 : at < toId ? -1 : at > toId ? 1 : 0;
}

function bsearchInsertEdge(rows: string[], fromId: string, toId: string): number {
    let lo = 0, hi = rows.length;
    while (lo < hi) {
        const mid = (lo + hi) >>> 1;
        if (cmpEdge(edgeSortKey(rows[mid]), fromId, toId) < 0) lo = mid + 1; else hi = mid;
    }
    return lo;
}

function bsearchFindEdge(rows: string[], fromId: string, toId: string): number {
    let lo = 0, hi = rows.length - 1;
    while (lo <= hi) {
        const mid = (lo + hi) >>> 1;
        const c = cmpEdge(edgeSortKey(rows[mid]), fromId, toId);
        if (c === 0) return mid;
        if (c < 0) lo = mid + 1; else hi = mid - 1;
    }
    return -1;
}

/** Upsert entity row: | ID | File | Aliases | — replaces existing row with same aliases[0], or inserts. */
export function insertEntityIntoIndex(dir: string, id: string, file: string, aliases: string[]): void {
    const indexPath = path.join(dir, "INDEX.entities.md");
    const {headerLines, dataRows} = readIndexTable(indexPath, ENTITY_INDEX_DEFAULT);
    const newRow = `| ${id} | ${file} | ${aliases.join(", ")} |`;
    const existing = bsearchFindEntity(dataRows, aliases[0] ?? "");
    if (existing >= 0) {
        dataRows[existing] = newRow;
    } else {
        dataRows.splice(bsearchInsertEntity(dataRows, aliases[0] ?? ""), 0, newRow);
    }
    writeIndexTable(indexPath, headerLines, dataRows);
}

/** Remove entity row by first alias (sort key). */
export function removeEntityFromIndex(dir: string, firstAlias: string): void {
    const indexPath = path.join(dir, "INDEX.entities.md");
    if (!fs.existsSync(indexPath)) return;
    const {headerLines, dataRows} = readIndexTable(indexPath, "");
    const idx = bsearchFindEntity(dataRows, firstAlias);
    if (idx >= 0) dataRows.splice(idx, 1);
    writeIndexTable(indexPath, headerLines, dataRows);
}

/** Insert edge row: | From ID | To ID | Relation | UUID | File | Last Verified |
 *  IDs are stored sorted (min first) for canonical direction. */
export function insertEdgeIntoIndex(
    dir: string, fromId: string, toId: string,
    relation: string, id: string, file: string, lastVerified: string
): void {
    const [a, b] = [fromId, toId].sort();
    const indexPath = path.join(dir, "INDEX.edges.md");
    const {headerLines, dataRows} = readIndexTable(indexPath, EDGE_INDEX_DEFAULT);
    const newRow = `| ${a} | ${b} | ${relation} | ${id} | ${file} | ${lastVerified} |`;
    const existing = bsearchFindEdge(dataRows, a, b);
    if (existing >= 0) {
        dataRows[existing] = newRow;
    } else {
        dataRows.splice(bsearchInsertEdge(dataRows, a, b), 0, newRow);
    }
    writeIndexTable(indexPath, headerLines, dataRows);
}

/** Remove edge row by (fromId, toId) pair — binary search. */
export function removeEdgeFromIndex(dir: string, fromId: string, toId: string): void {
    const [a, b] = [fromId, toId].sort();
    const indexPath = path.join(dir, "INDEX.edges.md");
    if (!fs.existsSync(indexPath)) return;
    const {headerLines, dataRows} = readIndexTable(indexPath, "");
    const idx = bsearchFindEdge(dataRows, a, b);
    if (idx >= 0) dataRows.splice(idx, 1);
    writeIndexTable(indexPath, headerLines, dataRows);
}

/** Update edge row's last-verified date — binary search. */
export function updateEdgeInIndex(
    dir: string, fromId: string, toId: string,
    relation: string, id: string, file: string, date: string
): void {
    const [a, b] = [fromId, toId].sort();
    const indexPath = path.join(dir, "INDEX.edges.md");
    if (!fs.existsSync(indexPath)) return;
    const {headerLines, dataRows} = readIndexTable(indexPath, "");
    const idx = bsearchFindEdge(dataRows, a, b);
    if (idx >= 0) dataRows[idx] = `| ${a} | ${b} | ${relation} | ${id} | ${file} | ${date} |`;
    writeIndexTable(indexPath, headerLines, dataRows);
}
