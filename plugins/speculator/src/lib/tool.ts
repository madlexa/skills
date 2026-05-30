import type {Command} from "commander";

export type JsonSchemaType =
    | "string"
    | "number"
    | "boolean"
    | "integer"
    | "array"
    | "object"
    | "null";

export interface PropertySchema {
    readonly type: JsonSchemaType;
    readonly description?: string;
}

export interface InputSchema<TInput extends object = Record<string, unknown>> {
    readonly type: "object";
    readonly properties: { readonly [K in keyof TInput]?: PropertySchema };
    readonly required?: readonly (keyof TInput & string)[];
}

/**
 * Carries both the TypeScript arg type T and its JSON Schema.
 * Use `defineType<T>(schema)` to construct.
 */
export interface CommandType<T extends object = Record<string, unknown>> {
    schema(): InputSchema<T>;
}

/** Factory: tie a TypeScript arg type T to its JSON Schema at construction. */
export function defineType<T extends object>(s: InputSchema<T>): CommandType<T> {
    return {schema: () => s};
}

/**
 * Single command interface for all speculator commands.
 * Method bivariance on `run` + covariant `type()` return ensure
 * SpeculatorCommand<Concrete> satisfies SpeculatorCommand (default Record<string,unknown>).
 */
export interface SpeculatorCommand<T extends object = Record<string, unknown>> {
    readonly name: string;
    readonly description: string;

    type(): CommandType<T>;

    register(program: Command): void;

    run(args: T, dir: string): Promise<string>;
}
