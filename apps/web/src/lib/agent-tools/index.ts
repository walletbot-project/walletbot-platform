import type { ToolName } from '@wallet-bot/shared'
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
    return toolExecutors[name as ToolName].execute(context, args)
}
