import type { ToolDefinition } from './tool-schema'
import { SchemaType } from './tool-schema'

// ── Tool definitions ─────────────────────────────────────────
// Demo tools — replace with real implementations as features are wired up.

export const TOOL_DEFINITIONS = [
    {
        name: 'addTransaction',
        description:
            'Add a new transaction. Use type "expense" when spending, "income" when receiving money, "transfer" when moving between accounts.',
        parameters: {
            type: SchemaType.OBJECT,
            properties: {
                type: {
                    type: SchemaType.STRING,
                    description: 'Transaction type',
                    enum: ['expense', 'income', 'transfer'],
                },
                amount: {
                    type: SchemaType.NUMBER,
                    description:
                        'The amount (e.g. 12.50 for twelve and fifty cents)',
                },
                description: {
                    type: SchemaType.STRING,
                    description: 'Brief description of the transaction',
                },
            },
            required: ['type', 'amount', 'description'],
        },
    },
    {
        name: 'listTransactions',
        description: 'List recent transactions. Supports filtering by type.',
        parameters: {
            type: SchemaType.OBJECT,
            properties: {
                type: {
                    type: SchemaType.STRING,
                    description: 'Filter by type. Optional.',
                    enum: ['expense', 'income', 'transfer'],
                },
            },
            required: [],
        },
    },
    {
        name: 'listAccounts',
        description: 'List all user accounts.',
        parameters: {
            type: SchemaType.OBJECT,
            properties: {},
            required: [],
        },
    },
] as const satisfies readonly ToolDefinition[]

// ── Derived types ────────────────────────────────────────────

export type ToolName = (typeof TOOL_DEFINITIONS)[number]['name']

export const TOOL_MAP = TOOL_DEFINITIONS.reduce<
    Record<ToolName, ToolDefinition>
>(
    (acc, tool) => {
        acc[tool.name] = tool
        return acc
    },
    {} as Record<ToolName, ToolDefinition>,
)
