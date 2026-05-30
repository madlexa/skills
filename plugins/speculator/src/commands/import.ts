import {Command} from "commander";
import * as fs from "node:fs";
import * as path from "node:path";
import {parse} from "yaml";
import {errMsg} from "../lib/command-utils";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";
import {addEdgeCommand, addEntityCommand, slugify} from "./add";
import {updateCommand} from "./update";

interface ImportArgs extends Record<string, unknown> {
    file: string;
}

interface YamlEntity {
    name: string;
    summary: string;
}

interface YamlEdge {
    from: string;
    to: string;
    relation: string;
    human?: string;
}

interface YamlGraph {
    entities?: YamlEntity[];
    edges?: YamlEdge[];
}

export const importCommand: SpeculatorCommand<ImportArgs> = {
    name: "import",
    description: "Bulk import entities and edges from a YAML file",

    type() {
        return defineType<ImportArgs>({
            type: "object",
            properties: {
                file: {type: "string", description: "Path to YAML file with entities and edges"},
            },
            required: ["file"],
        });
    },

    register(program: Command): void {
        program
            .command("import <file>")
            .description("Bulk import entities and edges from a YAML file")
            .action(async (file: string) => {
                const {dir} = program.opts<{dir: string}>();
                try {
                    console.log(await importCommand.run({file}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({file}: ImportArgs, dir: string): Promise<string> {
        const absFile = path.resolve(file);
        if (!fs.existsSync(absFile)) {
            throw new Error(`File not found: ${absFile}`);
        }

        const graph = parse(fs.readFileSync(absFile, "utf-8")) as YamlGraph;

        let entitiesCreated = 0, entitiesSkipped = 0;
        let edgesCreated = 0, edgesSkipped = 0;
        const skips: string[] = [];

        for (const entity of graph.entities ?? []) {
            try {
                await addEntityCommand.run({name: entity.name, summary: entity.summary}, dir);
                entitiesCreated++;
            } catch (e) {
                entitiesSkipped++;
                skips.push(`  skip entity '${entity.name}': ${e instanceof Error ? e.message : String(e)}`);
            }
        }

        for (const edge of graph.edges ?? []) {
            // entities are created from slugify(name); edge endpoints in the YAML
            // may use the same human-readable names, so slugify them identically
            // before lookup — otherwise every edge silently fails to resolve.
            const from = slugify(edge.from);
            const to = slugify(edge.to);
            try {
                await addEdgeCommand.run({from, to, relation: edge.relation}, dir);
                edgesCreated++;
                if (edge.human) {
                    await updateCommand.run({slug: from, to, section: "Human", content: edge.human.trim()}, dir);
                }
            } catch (e) {
                edgesSkipped++;
                skips.push(`  skip edge '${edge.from}→${edge.to}': ${e instanceof Error ? e.message : String(e)}`);
            }
        }

        const summary = `Imported: ${entitiesCreated} entities, ${edgesCreated} edges`;
        return skips.length > 0
            ? `${summary}\nSkipped: ${entitiesSkipped} entities, ${edgesSkipped} edges\n${skips.join("\n")}`
            : summary;
    },
};
