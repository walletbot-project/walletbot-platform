// Provider-agnostic schema types for agent tool definitions.
// String values match Google GenAI's Type enum exactly, so conversion is trivial.

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
