// Provider-agnostic schema types for agent tool definitions.
// Zod is the source of truth; this module provides the serializable format
// that consumers (Google GenAI, web declarations, etc.) convert from.

import { z } from 'zod'

// Serializable schema types

export const SchemaType = {
    STRING: 'STRING',
    NUMBER: 'NUMBER',
    INTEGER: 'INTEGER',
    BOOLEAN: 'BOOLEAN',
    ARRAY: 'ARRAY',
    OBJECT: 'OBJECT',
} as const

export type SchemaType = (typeof SchemaType)[keyof typeof SchemaType]

export interface ToolSchema {
    type: SchemaType
    description?: string
    properties?: Record<string, ToolSchema>
    required?: string[]
    enum?: string[]
    items?: ToolSchema
}

export interface ToolDefinition {
    name: string
    description: string
    parameters: ToolSchema
}

// Zod → ToolSchema converter

export function zodToToolSchema(schema: z.ZodType): ToolSchema {
    const desc = schema.description

    if (schema instanceof z.ZodObject) {
        const shape = schema.shape as Record<string, z.ZodType>
        const properties: Record<string, ToolSchema> = {}
        const required: string[] = []

        for (const [key, value] of Object.entries(shape)) {
            properties[key] = zodToToolSchema(value)
            if (!isOptional(value)) {
                required.push(key)
            }
        }

        return {
            type: SchemaType.OBJECT,
            properties,
            required,
            description: desc,
        }
    }

    if (schema instanceof z.ZodString) {
        return { type: SchemaType.STRING, description: desc }
    }

    if (schema instanceof z.ZodNumber) {
        return { type: SchemaType.NUMBER, description: desc }
    }

    if (schema instanceof z.ZodBoolean) {
        return { type: SchemaType.BOOLEAN, description: desc }
    }

    if (schema instanceof z.ZodEnum) {
        return {
            type: SchemaType.STRING,
            enum: schema.options as string[],
            description: desc,
        }
    }

    if (schema instanceof z.ZodOptional) {
        const inner = zodToToolSchema(schema.unwrap())
        return { ...inner, description: desc ?? inner.description }
    }

    if (schema instanceof z.ZodArray) {
        return {
            type: SchemaType.ARRAY,
            items: zodToToolSchema(schema.element),
            description: desc,
        }
    }

    throw new Error(
        `zodToToolSchema: unsupported Zod type: ${schema.constructor.name}`,
    )
}

function isOptional(schema: z.ZodType): boolean {
    return schema instanceof z.ZodOptional
}
