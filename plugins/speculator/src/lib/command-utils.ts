import type {Command} from "commander";
import {readEntityIndex, uniqueEntities} from "./index-reader";

/** Extract a clean error message without "Error: " prefix. */
export function errMsg(e: unknown): string {
    return e instanceof Error ? e.message : String(e);
}

/**
 * Builds a "not found" error message with fuzzy suggestions and an alias-fix instruction.
 * Pass `extraAction` to append a second option (e.g. "create it with add_entity()").
 */
export function notFoundMsg(
    slug: string,
    entities: ReturnType<typeof readEntityIndex>,
    extraAction?: string,
): string {
    const suggestions = suggestSlugs(slug, entities);
    const extra = extraAction ? `\nOr ${extraAction}.` : "";
    if (suggestions.length > 0) {
        const aliasFix = `add_alias("${suggestions[0]}", "${slug}")`;
        return (
            `'${slug}' not found.\nDid you mean:\n${suggestions.map((s) => `  - ${s}`).join("\n")}` +
            `\n\nIf one of these is correct, add an alias so future lookups work:\n  ${aliasFix}${extra}`
        );
    }
    return `'${slug}' not found. Use list_entities() to browse all slugs.${extra ? ` ${extra}.` : ""}`;
}

/** Returns up to `limit` slug suggestions for a missing slug. */
export function suggestSlugs(missing: string, entities: ReturnType<typeof readEntityIndex>, limit = 3): string[] {
    const seen = new Set<string>();
    const scored: Array<{ slug: string; score: number }> = [];
    const m = missing.toLowerCase();

    for (const ref of uniqueEntities(entities)) {
        const slug = ref.aliases[0];
        if (!slug || seen.has(slug)) continue;
        seen.add(slug);
        const s = slug.toLowerCase();
        // Substring match scores higher than pure edit distance
        const substringBonus = s.includes(m) || m.includes(s) ? 5 : 0;
        const dist = levenshtein(m, s);
        const maxLen = Math.max(m.length, s.length);
        const score = (1 - dist / maxLen) * 10 + substringBonus;
        if (score >= 3) scored.push({slug, score});
    }

    return scored
        .sort((a, b) => b.score - a.score)
        .slice(0, limit)
        .map((x) => x.slug);
}

/** Levenshtein distance between two strings. */
export function levenshtein(a: string, b: string): number {
    const dp: number[][] = Array.from({length: a.length + 1}, (_, i) =>
        Array.from({length: b.length + 1}, (_, j) => (i === 0 ? j : j === 0 ? i : 0))
    );
    for (let i = 1; i <= a.length; i++) {
        for (let j = 1; j <= b.length; j++) {
            dp[i][j] = a[i - 1] === b[j - 1]
                ? dp[i - 1][j - 1]
                : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
        }
    }
    return dp[a.length][b.length];
}

/**
 * Returns an existing subcommand by name or creates a new one.
 * Prevents duplicate subcommand registration when multiple commands
 * register under the same parent (e.g. "add entity" and "add edge").
 */
export function getOrCreate(
    program: Command,
    name: string,
    description: string
): Command {
    return (
        program.commands.find((c) => c.name() === name) ??
        program.command(name).description(description)
    );
}
