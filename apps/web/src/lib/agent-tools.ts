import type { ToolName } from '@wallet-bot/shared'
import { TOOL_DEFINITIONS } from '@wallet-bot/shared'
import type { ConvexClient } from 'convex/browser'
import type { ConvexReactClient } from 'convex/react'

// ── Types ──────────────────────────────────────────────────────

type ConvexClientLike = ConvexClient | ConvexReactClient

type ToolHandler = (
    convexClient: ConvexClientLike,
    args: Record<string, unknown>,
) => Promise<Record<string, unknown>>

// ── Tool declarations (derived from shared) ────────────────────

export const agentToolDeclarations = TOOL_DEFINITIONS.map((d) => ({
    name: d.name,
    description: d.description,
    parameters: d.parameters,
}))

// ── Tool handlers ──────────────────────────────────────────────
// Each tool name from shared MUST have a handler — adding a tool
// in shared without a handler here is a compile error.

const toolHandlers: Record<ToolName, ToolHandler> = {
    addTransaction: async () => {
        return { success: true, message: 'Mock: transaction added' }
    },
    listTransactions: async () => {
        return { transactions: [], count: 0 }
    },
    listAccounts: async () => {
        return { accounts: [] }
    },
}

// ── Tool execution ─────────────────────────────────────────────

export async function executeToolCall(
    convexClient: ConvexClientLike,
    name: string,
    args: Record<string, unknown>,
): Promise<Record<string, unknown>> {
    const handler = toolHandlers[name as ToolName]
    if (!handler) {
        return { error: `Unknown tool: ${name}` }
    }
    return handler(convexClient, args)
}
