import {Command} from "commander";
import * as fs from "node:fs";
import * as path from "node:path";
import {v4 as uuidv4} from "uuid";
import {errMsg} from "../lib/command-utils";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";

interface InitArgs extends Record<string, unknown> {
    target: string;
    noExample?: boolean;
}

export const initCommand: SpeculatorCommand<InitArgs> = {
    name: "init",
    description: "Initialize a new knowledge base directory",

    type() {
        return defineType<InitArgs>({
            type: "object",
            properties: {
                target: {type: "string", description: "Directory to initialize"},
                noExample: {type: "boolean", description: "Skip creating the example entity"},
            },
            required: ["target"],
        });
    },

    register(program: Command): void {
        program
            .command("init <target>")
            .description("Initialize a new knowledge base directory")
            .option("--no-example", "Skip creating the example entity")
            .action(async (target: string, opts: {example: boolean}) => {
                try {
                    console.log(await initCommand.run({target, noExample: !opts.example}, ""));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({target, noExample}: InitArgs, _dir: string): Promise<string> {
        const absDir = path.resolve(target);

        if (fs.existsSync(absDir)) {
            // A speculator KB is identified by its INDEX, not by mere non-emptiness.
            // Treating any non-empty directory as "already initialized" silently
            // no-ops (exit 0) on a real project root — e.g. `speculator init .` —
            // looking like success while creating nothing.
            if (fs.existsSync(path.join(absDir, "INDEX.entities.md"))) {
                return `Already initialized at: ${absDir}`;
            }
            const existing = fs.readdirSync(absDir).filter(f => !f.startsWith("."));
            if (existing.length > 0) {
                throw new Error(
                    `Refusing to initialize: ${absDir} is not empty and is not a speculator knowledge base. ` +
                    `Choose a new or empty directory, e.g. 'speculator init knowledge'.`
                );
            }
        }

        // Create directories
        fs.mkdirSync(path.join(absDir, "entities"), {recursive: true});
        fs.mkdirSync(path.join(absDir, "edges"), {recursive: true});

        const date = new Date().toISOString().slice(0, 10);

        let entityIndexRows = "";

        if (!noExample) {
            const exampleId = uuidv4();
            const exampleSlug = "example";

            const entityContent = `---
id: ${exampleId}
type: entity
name: Example
slug: ${exampleSlug}
summary: Example entity created by speculator init
tags: [example]
created: ${date}
---

# Example

## Human
This is an example entity created by \`speculator init\`.
Replace it with your own entities using \`speculator add entity\`.

## Context
Why this entity exists and what alternatives were considered.
Use this section for narrative decisions that are not obvious from the code.
`;

            fs.writeFileSync(
                path.join(absDir, "entities", `${exampleSlug}.md`),
                entityContent
            );

            entityIndexRows = `| ${exampleId} | entities/${exampleSlug}.md | ${exampleSlug} |\n`;
        }

        // Create INDEX.entities.md
        const entityIndex = `# Entity Index
_Sorted by first alias. Auto-generated — do not edit manually. Use \`speculator index rebuild\`_

| ID | File | Aliases |
|----|------|---------|
${entityIndexRows}`;

        fs.writeFileSync(path.join(absDir, "INDEX.entities.md"), entityIndex);

        // Create empty INDEX.edges.md
        const edgeIndex = `# Edge Index
_Sorted by from-id, then to-id. Auto-generated — do not edit manually._

| From ID | To ID | Relation | UUID | File | Last Verified |
|---------|-------|----------|------|------|--------------|
`;

        fs.writeFileSync(path.join(absDir, "INDEX.edges.md"), edgeIndex);

        if (noExample) {
            return `Initialized knowledge base at: ${absDir}\nCreated: entities/, edges/, INDEX files`;
        }

        return `Initialized knowledge base at: ${absDir}
Created: entities/, edges/, INDEX files, example entity

To remove the example: speculator --dir ${absDir} remove example
To start fresh:        delete entities/example.md`;
    },
};
