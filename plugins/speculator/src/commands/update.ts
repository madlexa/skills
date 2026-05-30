import {Command} from "commander";
import * as fs from "node:fs";
import * as path from "node:path";
import {parse as yamlParse} from "yaml";
import {matter, serialize, updateEdgeInIndex} from "../lib/document";
import {readEntityIndex, resolveEdge} from "../lib/index-reader";
import {errMsg, notFoundMsg} from "../lib/command-utils";
import type {SpeculatorCommand} from "../lib/tool";
import {defineType} from "../lib/tool";
import {today} from "../lib/date-utils";

function updateSection(filePath: string, sectionName: string, newContent: string): void {
    const raw = fs.readFileSync(filePath, "utf-8");
    const {data, content} = matter(raw);

    const lines = content.split("\n");
    const resultLines: string[] = [];
    let inTargetSection = false;
    let sectionFound = false;

    for (let i = 0; i < lines.length; i++) {
        const match = lines[i].match(/^## (.+)$/);
        if (match) {
            if (match[1].toLowerCase() === sectionName.toLowerCase()) {
                inTargetSection = true;
                sectionFound = true;
                resultLines.push(lines[i]);
                resultLines.push(newContent);
                resultLines.push("");
                continue;
            } else {
                inTargetSection = false;
            }
        }

        if (!inTargetSection) {
            resultLines.push(lines[i]);
        }
    }

    if (!sectionFound) {
        resultLines.push(`## ${sectionName}`);
        resultLines.push(newContent);
        resultLines.push("");
    }

    fs.writeFileSync(filePath, serialize(data) + "\n" + resultLines.join("\n"));
}

function updateEdgeLastVerified(filePath: string, date: string): void {
    const raw = fs.readFileSync(filePath, "utf-8");
    const {data, content} = matter(raw);
    data["last-verified"] = date;
    fs.writeFileSync(filePath, serialize(data) + "\n" + content);
}

interface UpdateArgs extends Record<string, unknown> {
    slug: string;
    to?: string;      // present → edge operation or touch
    section?: string;
    content?: string;
    metadata?: string;
}

export const updateCommand: SpeculatorCommand<UpdateArgs> = {
    name: "update",
    description:
        "Update entity or edge. " +
        "3 args (slug section content): update entity section. " +
        "4 args (slug to section content): update edge section. " +
        "2 args (slug to): touch edge last-verified.",

    type() {
        return defineType<UpdateArgs>({
            type: "object",
            properties: {
                slug: {type: "string", description: "Entity slug"},
                to: {type: "string", description: "Target entity slug — triggers edge mode"},
                section: {type: "string", description: "Section name to update"},
                content: {type: "string", description: "New content for the section"},
                metadata: {type: "string", description: "Frontmatter field to update (e.g. summary, tags)"},
            },
            required: ["slug"],
        });
    },

    register(program: Command): void {
        program
            .command("update <args...>")
            .description(
                "Update entity section, edge section, or touch edge.\n" +
                "  update <slug> <section> <content>                   — entity section\n" +
                "  update <slug> <to> <section> <content>              — edge section\n" +
                "  update <slug> <to>                                   — touch edge\n" +
                "  update <slug> --metadata <field> <value>            — frontmatter field"
            )
            .option("--metadata <field>", "Update frontmatter field (e.g. summary, tags)")
            .action(async (args: string[], opts: { metadata?: string }) => {
                const {dir} = program.opts<{ dir: string }>();
                try {
                    let parsed: UpdateArgs;
                    if (opts.metadata) {
                        parsed = {slug: args[0], metadata: opts.metadata, content: args[1]};
                    } else if (args.length === 2) {
                        parsed = {slug: args[0], to: args[1]};
                    } else if (args.length === 3) {
                        parsed = {slug: args[0], section: args[1], content: args[2]};
                    } else if (args.length === 4) {
                        parsed = {slug: args[0], to: args[1], section: args[2], content: args[3]};
                    } else {
                        throw new Error("Wrong number of arguments. Use: update <slug> <section> <content>  |  update <slug> <to> <section> <content>  |  update <slug> <to>  |  update <slug> --metadata <field> <value>");
                    }
                    console.log(await updateCommand.run(parsed, dir));
                } catch (e) {
                    console.error(errMsg(e));
                    process.exit(1);
                }
            });
    },

    async run({slug, to, section, content, metadata}: UpdateArgs, dir: string): Promise<string> {
        const entities = readEntityIndex(dir);

        // Frontmatter field update (--metadata)
        if (metadata && content !== undefined) {
            const PROTECTED = ["id", "slug", "type", "created"];
            if (PROTECTED.includes(metadata))
                throw new Error(`Field '${metadata}' is protected and cannot be updated.`);
            const ref = entities.get(slug);
            if (!ref) throw new Error(notFoundMsg(slug, entities));
            const raw = fs.readFileSync(path.join(dir, ref.file), "utf-8");
            const {data, content: body} = matter(raw);
            // Only the structured `tags` field is parsed as YAML; scalar fields
            // (summary, name, …) are stored verbatim. Otherwise a value like
            // "Payment: the gateway", "null", or "123" would be silently coerced
            // into an object/null/number, corrupting the frontmatter.
            if (metadata === "tags") {
                const parsed = yamlParse(content);
                data[metadata] = Array.isArray(parsed)
                    ? parsed
                    : content.split(",").map((s) => s.trim()).filter(Boolean);
            } else {
                data[metadata] = content;
            }
            fs.writeFileSync(path.join(dir, ref.file), serialize(data) + "\n" + body);
            return `Updated ${slug}.${metadata}`;
        }

        // Touch edge (slug + to, no section/content)
        if (to && !section && !content) {
            const {edgeRef} = resolveEdge(dir, slug, to);
            const filePath = path.join(dir, edgeRef.file);
            const date = today();
            updateEdgeLastVerified(filePath, date);
            updateEdgeInIndex(dir, edgeRef.fromId, edgeRef.toId, edgeRef.relation, edgeRef.id, edgeRef.file, date);
            return `Touched edge ${slug} → ${to}: last-verified = ${date}`;
        }

        // Edge section update (slug + to + section + content)
        if (to && section && content !== undefined) {
            const {edgeRef} = resolveEdge(dir, slug, to);
            updateSection(path.join(dir, edgeRef.file), section, content.replace(/\\n/g, "\n"));
            return `Updated edge ${slug} → ${to} section: ${section}`;
        }

        // Entity section update (slug + section + content)
        if (!to && section && content !== undefined) {
            const ref = entities.get(slug);
            if (!ref) throw new Error(notFoundMsg(slug, entities));
            updateSection(path.join(dir, ref.file), section, content.replace(/\\n/g, "\n"));
            return `Updated ${slug} section: ${section}`;
        }

        throw new Error("Wrong arguments. Use: update(slug, section, content) for entity section, update(slug, to, section, content) for edge section, update(slug, to) to touch edge.");
    },
};
