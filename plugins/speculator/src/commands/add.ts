import {Command} from "commander";
import * as fs from "node:fs";
import * as path from "node:path";
import {v4 as uuidv4} from "uuid";
import {
    Document,
    type EdgeFrontmatter,
    type EntityFrontmatter,
    insertEdgeIntoIndex,
    insertEntityIntoIndex,
    matter,
    serialize
} from "../lib/document";
import {binarySearchEdge, readEdgeIndex, readEntityIndex} from "../lib/index-reader";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";
import {errMsg, getOrCreate, notFoundMsg} from "../lib/command-utils";
import {today} from "../lib/date-utils";
import {indexRebuildCommand} from "./index";

export function slugify(name: string): string {
    return name
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-|-$/g, "");
}

interface AddEntityArgs extends Record<string, unknown> {
    name: string;
    summary: string;
}

interface AddEdgeArgs extends Record<string, unknown> {
    from: string;
    to: string;
    relation: string;
}

interface AddAliasArgs extends Record<string, unknown> {
    slug: string;
    alias: string;
}

export const addEntityCommand: SpeculatorCommand<AddEntityArgs> = {
    name: "add_entity",
    description: "Create a new entity in the knowledge base",

    type() {
        return defineType<AddEntityArgs>({
            type: "object",
            properties: {
                name: {type: "string", description: "Entity name"},
                summary: {type: "string", description: "Short summary"},
            },
            required: ["name", "summary"],
        });
    },

    register(program: Command): void {
        const add = getOrCreate(program, "add", "Add a new entity or edge");

        add
            .command("entity <name> <summary>")
            .description("Add a new entity to the knowledge base")
            .action(async (name: string, summary: string) => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    console.log(await addEntityCommand.run({name, summary}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({name: entityName, summary}: AddEntityArgs, dir: string): Promise<string> {
        const id = uuidv4();
        const slug = slugify(entityName);
        if (!slug) {
            throw new Error(`Name '${entityName}' has no slug-safe characters (letters or digits). Choose a name that includes at least one a–z or 0–9 character.`);
        }
        const date = today();

        const entities = readEntityIndex(dir);
        if (entities.has(slug)) throw new Error(`'${slug}' already exists. Use get('${slug}') to read it, or update() to modify a section.`);

        const fm: EntityFrontmatter = {
            id,
            type: "entity",
            name: entityName,
            slug,
            summary,
            tags: ["domain"],
            created: date
        };
        Document.entity(fm).write(dir);
        insertEntityIntoIndex(dir, id, `entities/${slug}.md`, [slug]);

        return `Created entity: ${slug}`;
    },
};

export const addEdgeCommand: SpeculatorCommand<AddEdgeArgs> = {
    name: "add_edge",
    description: "Create a new edge between two entities",

    type() {
        return defineType<AddEdgeArgs>({
            type: "object",
            properties: {
                from: {type: "string", description: "Source entity slug"},
                to: {type: "string", description: "Target entity slug"},
                relation: {type: "string", description: "Relation label"},
            },
            required: ["from", "to", "relation"],
        });
    },

    register(program: Command): void {
        const add = getOrCreate(program, "add", "Add a new entity or edge");

        add
            .command("edge <from-slug> <to-slug> <relation>")
            .description("Add a new edge between two entities")
            .action(async (from: string, to: string, relation: string) => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    console.log(await addEdgeCommand.run({from, to, relation}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({from: fromSlug, to: toSlug, relation}: AddEdgeArgs, dir: string): Promise<string> {
        const entities = readEntityIndex(dir);
        const fromEntity = entities.get(fromSlug);
        const toEntity = entities.get(toSlug);

        if (!fromEntity) throw new Error(notFoundMsg(fromSlug, entities, `create it first with add_entity("${fromSlug}", "summary")`));
        if (!toEntity) throw new Error(notFoundMsg(toSlug, entities, `create it first with add_entity("${toSlug}", "summary")`));

        const edgeRefs = readEdgeIndex(dir);
        const [a, b] = [fromEntity.id, toEntity.id].sort();
        if (binarySearchEdge(edgeRefs, a, b)) {
            throw new Error(`Edge between '${fromSlug}' and '${toSlug}' already exists.\nTo add content: speculator update ${fromSlug} ${toSlug} <section> "<content>"`);
        }

        // `relation` becomes part of both the pipe-delimited edge index row and
        // the on-disk edge filename. A `|`/newline mis-columns the index row on
        // read (the edge becomes unrecoverable); a `/` or `\` escapes the edges/
        // directory on write (path traversal). Relations are short verb phrases,
        // so reject the structural characters rather than silently mangling them.
        const cleanRelation = relation.trim();
        if (!cleanRelation) {
            throw new Error(`Relation cannot be empty. Provide a verb phrase, e.g. "calls" or "stored_in".`);
        }
        if (/[|/\\\r\n]/.test(cleanRelation)) {
            throw new Error(`Relation '${relation}' contains an illegal character. Relations may not contain | / \\ or newlines.`);
        }

        const id = uuidv4();
        const date = today();
        const slug = `${fromSlug}--${cleanRelation.replace(/_/g, "-")}--${toSlug}`;

        const fm: EdgeFrontmatter = {
            id,
            type: "edge",
            "from-id": fromEntity.id,
            "to-id": toEntity.id,
            relation: cleanRelation,
            created: date,
            "last-verified": date,
        };

        const fromDisplay = fromEntity.aliases[0] ?? fromSlug;
        const toDisplay = toEntity.aliases[0] ?? toSlug;
        // Use explicit slug for edge file path
        const fmWithSlug = {...fm, slug};
        Document.edge(fmWithSlug).write(dir, fromDisplay, toDisplay);
        insertEdgeIntoIndex(dir, fromEntity.id, toEntity.id, cleanRelation, id, `edges/${slug}.md`, date);

        return `Created edge: ${slug}`;
    },
};

interface RemoveAliasArgs extends Record<string, unknown> {
    slug: string;
    alias: string;
}

export const removeAliasCommand: SpeculatorCommand<RemoveAliasArgs> = {
    name: "remove_alias",
    description: "Remove an alias from an entity. Cannot remove the canonical slug.",

    type() {
        return defineType<RemoveAliasArgs>({
            type: "object",
            properties: {
                slug: {type: "string", description: "Entity slug or any of its current aliases"},
                alias: {type: "string", description: "Alias to remove"},
            },
            required: ["slug", "alias"],
        });
    },

    register(program: Command): void {
        program
            .command("remove-alias <slug> <alias>")
            .description("Remove an alias from an entity")
            .action(async (slug: string, alias: string) => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    console.log(await removeAliasCommand.run({slug, alias}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({slug, alias}: RemoveAliasArgs, dir: string): Promise<string> {
        const entities = readEntityIndex(dir);
        const entity = entities.get(slug);
        if (!entity) throw new Error(notFoundMsg(slug, entities));

        const filePath = path.join(dir, entity.file);
        const raw = fs.readFileSync(filePath, "utf-8");
        const {data: rawData, content} = matter(raw);

        // Canonical slug lives in fm.slug — cannot be removed
        if (rawData.slug === alias) {
            throw new Error(`'${alias}' is the canonical slug and cannot be removed as an alias. Use remove('${alias}') to delete the entity entirely.`);
        }

        const aliases: string[] = Array.isArray(rawData.aliases) ? [...(rawData.aliases as string[])] : [];
        if (!aliases.includes(alias)) throw new Error(`Alias '${alias}' not found on this entity. Call get('${slug}') to see its current aliases.`);
        if (aliases.length === 1) throw new Error(`Cannot remove the last alias. Add another alias first with add_alias(), then remove this one.`);

        const filtered = aliases.filter((a) => a !== alias);
        const data: Record<string, unknown> = {...rawData, aliases: filtered};

        fs.writeFileSync(filePath, `${serialize(data)}\n${content}`);

        await indexRebuildCommand.run({}, dir);
        return `Removed alias "${alias}" from ${entity.aliases[0]}`;
    },
};

export const addAliasCommand: SpeculatorCommand<AddAliasArgs> = {
    name: "add_alias",
    description: "Add an alias (alternative slug) to an existing entity",

    type() {
        return defineType<AddAliasArgs>({
            type: "object",
            properties: {
                slug: {type: "string", description: "Entity slug"},
                alias: {type: "string", description: "Alias to add"},
            },
            required: ["slug", "alias"],
        });
    },

    register(program: Command): void {
        const add = getOrCreate(program, "add", "Add a new entity or edge");

        add
            .command("alias <slug> <alias>")
            .description("Add an alias to an existing entity")
            .action(async (slug: string, alias: string) => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    console.log(await addAliasCommand.run({slug, alias}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({slug, alias: rawAlias}: AddAliasArgs, dir: string): Promise<string> {
        // Aliases are alternative slugs and are stored in the comma-delimited
        // aliases column of the pipe-delimited INDEX table. Normalize them with
        // the same slugify() that add_entity applies to names, otherwise a `|`
        // or `,` in the alias silently corrupts the index row (mis-columned on
        // read) and the alias becomes unrecoverable.
        const alias = slugify(rawAlias);
        if (!alias) throw new Error(`Alias '${rawAlias}' is empty after normalization. Aliases may contain only letters, digits, and hyphens.`);

        const entities = readEntityIndex(dir);
        const entity = entities.get(slug);
        if (!entity) throw new Error(notFoundMsg(slug, entities));

        // Check alias is not already taken
        if (entities.has(alias)) {
            const existing = entities.get(alias)!;
            if (existing.id === entity.id) throw new Error(`'${alias}' is already an alias of this entity.`);
            throw new Error(`'${alias}' is already used by entity '${existing.aliases[0]}'. Choose a different alias.`);
        }

        const filePath = path.join(dir, entity.file);
        const raw = fs.readFileSync(filePath, "utf-8");
        const {data: rawData, content} = matter(raw);

        const aliases: string[] = Array.isArray(rawData.aliases) ? [...(rawData.aliases as string[])] : [];
        if (aliases.includes(alias)) throw new Error(`'${alias}' is already an alias of this entity.`);
        aliases.push(alias);
        const data = {...rawData, aliases};

        fs.writeFileSync(filePath, `${serialize(data)}\n${content}`);

        await indexRebuildCommand.run({}, dir);
        return `Added alias "${alias}" to ${slug}`;
    },
};
