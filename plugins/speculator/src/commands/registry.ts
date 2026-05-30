import type {Command} from "commander";
import type {SpeculatorCommand} from "../lib/tool";

import {getCommand} from "./get";
import {listEdgesCommand, listEntitiesCommand} from "./list";
import {addAliasCommand, addEdgeCommand, addEntityCommand, removeAliasCommand} from "./add";
import {validateCommand} from "./validate";
import {updateCommand} from "./update";
import {indexRebuildCommand} from "./index";
import {removeCommand} from "./remove";
import {initCommand} from "./init";
import {importCommand} from "./import";
import {searchCommand} from "./search";
import {statsCommand} from "./stats";
import {exportCommand} from "./export";

/** MCP-exposed tools */
export const allTools: SpeculatorCommand[] = [
    getCommand,
    listEntitiesCommand,
    listEdgesCommand,
    addEntityCommand,
    addEdgeCommand,
    addAliasCommand,
    removeAliasCommand,
    validateCommand,
    updateCommand,
    indexRebuildCommand,
    removeCommand,
    searchCommand,
    statsCommand,
    exportCommand,
];

/** All commands including CLI-only ones */
const allCommands: SpeculatorCommand[] = [
    ...allTools,
    initCommand,
    importCommand,
];

export function registerAllCommands(program: Command): void {
    for (const cmd of allCommands) {
        cmd.register(program);
    }
}
