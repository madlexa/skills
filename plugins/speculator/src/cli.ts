#!/usr/bin/env node
import {Command} from "commander";
import * as path from "node:path";
import {registerAllCommands} from "./commands/registry";

const program = new Command();

program
    .name("speculator")
    .description("Graph-oriented knowledge base in Markdown files")
    .version("0.1.5")
    .option(
        "--dir <path>",
        "Knowledge base directory (default: ./knowledge/ or SPECULATOR_DIR)",
        process.env.SPECULATOR_DIR ?? path.resolve("./knowledge")
    );

process.on("uncaughtException", (e) => {
    process.stderr.write(`Unexpected error: ${e.message}\nRun speculator --help for usage.\n`);
    process.exit(1);
});
process.on("unhandledRejection", (e) => {
    const msg = e instanceof Error ? e.message : String(e);
    process.stderr.write(`Unexpected error: ${msg}\nRun speculator --help for usage.\n`);
    process.exit(1);
});

registerAllCommands(program);

program.parse();
