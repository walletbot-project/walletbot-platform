'use node'

// Adapter from the shared tool definitions to Google GenAI's
// `FunctionDeclaration` shape.
//
// `'use node'` because `Type` is a runtime value from `@google/genai`. Its only
// caller, `agent/runner.ts`, is a Node action, so the import-chain rule in
// CLAUDE.md is satisfied.
//
// The voice channel converts the same shared definitions without the SDK
// (`live/createToken.ts` writes Google's REST JSON by hand) so that minting a
// token never pulls a Node cold start. Same wire bytes, two encoders: if a
// schema quirk shows up in one, check the other.

import type { FunctionDeclaration, Schema } from '@google/genai'
import { Type } from '@google/genai'
import type { ToolSchema } from '@wallet-bot/shared'

const SCHEMA_TYPE_MAP: Record<string, Type> = {
    STRING: Type.STRING,
    NUMBER: Type.NUMBER,
    INTEGER: Type.INTEGER,
    BOOLEAN: Type.BOOLEAN,
    ARRAY: Type.ARRAY,
    OBJECT: Type.OBJECT,
}

export function toGoogleSchema(schema: ToolSchema): Schema {
    const result: Schema = {
        type: SCHEMA_TYPE_MAP[schema.type],
        description: schema.description,
        enum: schema.enum,
        required: schema.required,
    }
    if (schema.properties) {
        result.properties = Object.fromEntries(
            Object.entries(schema.properties).map(([k, v]) => [
                k,
                toGoogleSchema(v),
            ]),
        )
    }
    if (schema.items) {
        result.items = toGoogleSchema(schema.items)
    }
    return result
}

export function toFunctionDeclarations(
    defs: readonly {
        name: string
        description: string
        parameters: ToolSchema
    }[],
): FunctionDeclaration[] {
    return defs.map((d) => ({
        name: d.name,
        description: d.description,
        parameters: toGoogleSchema(d.parameters),
    }))
}
