import { TOOL_DEFINITIONS } from '@wallet-bot/shared'
import type { ConvexReactClient } from 'convex/react'
import type { z } from 'zod'

// Tool declarations (derived from shared)

export const agentToolDeclarations = TOOL_DEFINITIONS.map((d) => ({
    name: d.name,
    description: d.description,
    parameters: d.parameters,
}))

export type AgentToolContext = {
    client: ConvexReactClient
}

// Tool executors
// Each tool from shared MUST have an executor — adding a tool in
// shared without one here is a compile error (satisfies check).

export interface ToolExecutor {
    execute: (
        context: AgentToolContext,
        args: Record<string, unknown>,
    ) => Promise<Record<string, unknown>>
}

/** Bundle a Zod schema + typed handler into a validated executor. */
export function defineTool<T extends z.ZodType>(
    schema: T,
    handler: (
        context: AgentToolContext,
        args: z.infer<T>,
    ) => Promise<Record<string, unknown>>,
): ToolExecutor {
    return {
        execute: async (context, args) => {
            const parsed = schema.safeParse(args)
            if (!parsed.success) {
                return {
                    error: `Invalid args: ${parsed.error.message}`,
                }
            }
            return handler(context, parsed.data)
        },
    }
}
