import {Command} from "commander";
import * as fs from "node:fs";
import * as path from "node:path";
import {Document, type EdgeFrontmatter, type EntityFrontmatter} from "../lib/document";
import {readEdgeIndex, readEntityIndex, uniqueEntities} from "../lib/index-reader";
import {errMsg} from "../lib/command-utils";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";

export const validateCommand: SpeculatorCommand = {
    name: "validate",
    description: "Validate knowledge base integrity",

    type() {
        return defineType({type: "object", properties: {}, required: []});
    },

    register(program: Command): void {
        program
            .command("validate")
            .description("Validate knowledge base integrity")
            .action(async () => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    console.log(await validateCommand.run({}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run(_args: Record<string, unknown>, dir: string): Promise<string> {
        const errors: string[] = [];
        const entities = readEntityIndex(dir);
        const edgeRefs = readEdgeIndex(dir);
        const allEntities = uniqueEntities(entities);

        // No duplicate entity UUIDs
        const seenIds = new Set<string>();
        for (const ent of allEntities) {
            if (seenIds.has(ent.id)) errors.push(`Duplicate entity UUID: ${ent.id}`);
            seenIds.add(ent.id);
        }
        for (const edge of edgeRefs) {
            if (seenIds.has(edge.id)) errors.push(`Duplicate UUID: ${edge.id} (edge ${edge.fromId} → ${edge.toId})`);
            seenIds.add(edge.id);
        }

        // Entity files exist and IDs match
        for (const ent of allEntities) {
            const filePath = path.join(dir, ent.file);
            if (!fs.existsSync(filePath)) {
                errors.push(`Entity file missing: ${ent.file}`);
            } else {
                const fm = Document.read<EntityFrontmatter>(filePath).frontmatter;
                if (fm.id !== ent.id) {
                    errors.push(`Entity ID mismatch: INDEX has ${ent.id}, file has ${fm.id} (${ent.aliases[0]})`);
                }
            }
        }

        // Edge files exist and references are valid
        let deprecatedCount = 0;
        for (const edge of edgeRefs) {
            const filePath = path.join(dir, edge.file);
            if (!fs.existsSync(filePath)) {
                errors.push(`Edge file missing: ${edge.file}`);
                continue;
            }
            const fm = Document.read<EdgeFrontmatter>(filePath).frontmatter;

            if (fm.deprecated) {
                deprecatedCount++;
                continue;
            }

            if (!entities.get(fm["from-id"])) {
                errors.push(`Edge ${edge.file}: from-id ${fm["from-id"]} not found in entity index`);
            }
            if (!entities.get(fm["to-id"])) {
                errors.push(`Edge ${edge.file}: to-id ${fm["to-id"]} not found in entity index`);
            }
        }

        // File counts match INDEX
        const entitiesDir = path.join(dir, "entities");
        if (fs.existsSync(entitiesDir)) {
            const count = fs.readdirSync(entitiesDir).filter((f) => f.endsWith(".md")).length;
            if (count !== allEntities.length) {
                errors.push(`Entity count mismatch: INDEX has ${allEntities.length}, directory has ${count} files`);
            }
        }
        const edgesDir = path.join(dir, "edges");
        if (fs.existsSync(edgesDir)) {
            const count = fs.readdirSync(edgesDir).filter((f) => f.endsWith(".md")).length;
            if (count !== edgeRefs.length) {
                errors.push(`Edge count mismatch: INDEX has ${edgeRefs.length}, directory has ${count} files`);
            }
        }

        if (errors.length > 0) {
            throw new Error("Knowledge base has integrity issues. Fix them and run validate again:\n" + errors.map((e) => `  - ${e}`).join("\n"));
        }
        const suffix = deprecatedCount > 0 ? ` (${deprecatedCount} deprecated edge${deprecatedCount > 1 ? "s" : ""} skipped)` : "";
        return `Validation passed.${suffix}`;
    },
};
