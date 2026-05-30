import * as fs from "node:fs";
import * as path from "node:path";
import {Command} from "commander";
import {binarySearchEdge, readEdgeIndex, readEntityIndex} from "../lib/index-reader";
import {removeEdgeFromIndex, removeEntityFromIndex} from "../lib/document";
import {errMsg, notFoundMsg} from "../lib/command-utils";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";

interface RemoveArgs extends Record<string, unknown> {
    name: string;
    name2?: string;
}

export const removeCommand: SpeculatorCommand<RemoveArgs> = {
    name: "remove",
    description: "Remove entity (+ all its edges) or edge. remove(name) or remove(name, name2) — order of names doesn't matter",

    type() {
        return defineType<RemoveArgs>({
            type: "object",
            properties: {
                name: {type: "string", description: "Entity slug, or first entity slug for edge removal"},
                name2: {
                    type: "string",
                    description: "Second entity slug — if given, removes the edge between name and name2"
                },
            },
            required: ["name"],
        });
    },

    register(program: Command): void {
        program
            .command("remove <name> [name2]")
            .description("Remove entity (+ its edges) or edge between two entities")
            .action(async (name: string, name2: string | undefined) => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    console.log(await removeCommand.run({name, name2}, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({name, name2}: RemoveArgs, dir: string): Promise<string> {
        const entities = readEntityIndex(dir);

        if (!name2) {
            // Remove entity + all edges it participates in
            const entity = entities.get(name);
            if (!entity) throw new Error(notFoundMsg(name, entities));

            const edgeRefs = readEdgeIndex(dir);
            const connected = edgeRefs.filter(
                (e) => e.fromId === entity.id || e.toId === entity.id
            );

            for (const edge of connected) {
                fs.unlinkSync(path.join(dir, edge.file));
                removeEdgeFromIndex(dir, edge.fromId, edge.toId);
            }

            fs.unlinkSync(path.join(dir, entity.file));
            removeEntityFromIndex(dir, entity.aliases[0]);

            const edgeCount = connected.length;
            return `Removed entity: ${name}${edgeCount > 0 ? ` (+ ${edgeCount} edge${edgeCount > 1 ? "s" : ""})` : ""}`;
        }

        // Remove edge between two entities — order-agnostic
        const a = entities.get(name);
        const b = entities.get(name2);
        if (!a) throw new Error(notFoundMsg(name, entities));
        if (!b) throw new Error(notFoundMsg(name2, entities));

        const edgeRefs = readEdgeIndex(dir);
        const [smallerId, largerId] = [a.id, b.id].sort();
        const edge = binarySearchEdge(edgeRefs, smallerId, largerId);
        if (!edge) throw new Error(`No edge between '${name}' and '${name2}'. Use list_edges() to verify it exists.`);

        fs.unlinkSync(path.join(dir, edge.file));
        removeEdgeFromIndex(dir, edge.fromId, edge.toId);

        return `Removed edge: ${name} ↔ ${name2} [${edge.relation}]`;
    },
};
