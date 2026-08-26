import { type ToolName, withToolHint } from '@wallet-bot/shared'
import { toolExecutors } from './executors'
import type { AgentToolContext } from './helpers'

// Tool execution

export async function executeToolCall(
    context: AgentToolContext,
    name: string,
    args: Record<string, unknown>,
): Promise<Record<string, unknown>> {
    if (!(name in toolExecutors)) {
        return { error: `Unknown tool: ${name}` }
    }
    const result = await toolExecutors[name as ToolName].execute(context, args)
    // Static suggestion hints ride on the result rather than the system
    // prompt, so they land in the turn where they matter. Native does the same
    // in ToolExecutors.execute.
    return withToolHint(name, result)
}
