import type { z } from 'zod'
import { toolSchemas } from './definitions'
import type { ToolDefinition } from './helpers'
import { zodToToolSchema } from './helpers'

export { toolSchemas } from './definitions'

const toolDescriptions = {
    addTransaction:
        'Add a new transaction. Use type "expense" when spending, "income" when receiving money, "transfer" when moving between accounts.',
    listTransactions: 'List recent transactions. Supports filtering by type.',
    listAccounts: 'List all user accounts.',
} as const satisfies Record<keyof typeof toolSchemas, string>

// Derived types

export type ToolName = keyof typeof toolSchemas

export type ToolArgs<T extends ToolName> = z.infer<(typeof toolSchemas)[T]>

export type ToolsMap = Record<ToolName, ToolDefinition>

// Serialized definitions (for consumers that need plain objects)

export const TOOL_DEFINITIONS = (Object.keys(toolSchemas) as ToolName[]).map(
    (name) =>
        ({
            name,
            description: toolDescriptions[name],
            parameters: zodToToolSchema(toolSchemas[name]),
        }) satisfies ToolDefinition,
)

export const TOOL_MAP = TOOL_DEFINITIONS.reduce<ToolsMap>((acc, tool) => {
    acc[tool.name as ToolName] = tool
    return acc
}, {} as ToolsMap)
