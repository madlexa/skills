import type {EdgeRef} from "./index-reader";

export interface GraphEdge {
    targetId: string;
    edgeFile: string;
    relation: string;
}

export interface PathStep {
    fromId: string;
    toId: string;
    edgeFile: string;
    relation: string;
}

export type Graph = Map<string, GraphEdge[]>;

export function buildGraph(edgeRefs: EdgeRef[]): Graph {
    const graph: Graph = new Map();

    for (const edge of edgeRefs) {
        // Add bidirectional edges for BFS (graph is undirected for traversal)
        if (!graph.has(edge.fromId)) graph.set(edge.fromId, []);
        graph.get(edge.fromId)!.push({
            targetId: edge.toId,
            edgeFile: edge.file,
            relation: edge.relation,
        });

        if (!graph.has(edge.toId)) graph.set(edge.toId, []);
        graph.get(edge.toId)!.push({
            targetId: edge.fromId,
            edgeFile: edge.file,
            relation: edge.relation,
        });
    }

    return graph;
}

/** Find ALL paths between two nodes (up to maxPaths). Returns paths in order of length. */
export function bfsAllPaths(
    graph: Graph,
    fromId: string,
    toId: string,
    maxPaths = 10
): PathStep[][] {
    if (fromId === toId) return [[]];

    const results: PathStep[][] = [];
    // Each queue entry: [currentId, path so far, visited set]
    const queue: Array<[string, PathStep[], Set<string>]> = [[fromId, [], new Set([fromId])]];

    while (queue.length > 0 && results.length < maxPaths) {
        const [currentId, pathSoFar, visited] = queue.shift()!;

        // Prune: once we found paths, don't explore longer ones
        if (results.length > 0 && pathSoFar.length >= results[0].length) continue;

        const neighbors = graph.get(currentId) ?? [];
        for (const neighbor of neighbors) {
            if (visited.has(neighbor.targetId)) continue;

            const newPath: PathStep[] = [
                ...pathSoFar,
                {
                    fromId: currentId,
                    toId: neighbor.targetId,
                    edgeFile: neighbor.edgeFile,
                    relation: neighbor.relation,
                },
            ];

            if (neighbor.targetId === toId) {
                results.push(newPath);
            } else {
                queue.push([neighbor.targetId, newPath, new Set([...visited, neighbor.targetId])]);
            }
        }
    }

    return results;
}
