import * as path from "node:path";
import type {PathStep} from "./graph";
import type {EntityRef} from "./index-reader";
import {Document, type EdgeFrontmatter} from "./document";

interface ResolvedStep {
    fromName: string;
    toName: string;
    relation: string;
    edge: Document<EdgeFrontmatter>;
}

function resolveSteps(
    steps: PathStep[],
    entities: Map<string, EntityRef>,
    dir: string
): ResolvedStep[] {
    const idToName = new Map<string, string>();
    for (const ent of entities.values()) {
        idToName.set(ent.id, ent.aliases[0] ?? ent.id);
    }

    return steps.map((step) => ({
        fromName: idToName.get(step.fromId) ?? step.fromId,
        toName: idToName.get(step.toId) ?? step.toId,
        relation: step.relation,
        edge: Document.read<EdgeFrontmatter>(path.join(dir, step.edgeFile)),
    }));
}

export function formatNav(
    steps: PathStep[],
    entities: Map<string, EntityRef>,
    dir: string
): string {
    const resolved = resolveSteps(steps, entities, dir);
    const lines: string[] = [];

    for (let i = 0; i < resolved.length; i++) {
        const s = resolved[i];
        lines.push(`# ${s.fromName} ↔ ${s.toName} [${s.relation}]`);
        lines.push("");

        for (const [heading, body] of s.edge.sections) {
            lines.push(`## ${heading}`);
            lines.push(body);
            lines.push("");
        }

        if (i < resolved.length - 1) {
            lines.push("---");
            lines.push("");
        }
    }

    return lines.join("\n");
}
