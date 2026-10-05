import { ConvexError } from 'convex/values'

// `kind` of the `ConvexError` `agent/tools.ts:execute` throws for arguments
// the model got wrong. Only a `ConvexError`'s data survives the `runMutation`
// boundary, so this is how `agent/runner.ts` learns why a tool call threw.
const AGENT_TOOL_ERROR = 'agent_tool_error'

type AgentToolErrorData = {
    kind: typeof AGENT_TOOL_ERROR
    reason: 'invalid_args'
    message: string
}

export const invalidToolArgsError = (
    error: unknown,
): ConvexError<AgentToolErrorData> =>
    new ConvexError<AgentToolErrorData>({
        kind: AGENT_TOOL_ERROR,
        reason: 'invalid_args',
        message: error instanceof Error ? error.message : String(error),
    })

/** The coded data of a tool-call throw, or `null` for anything else. */
export const agentToolErrorOf = (error: unknown): AgentToolErrorData | null => {
    if (!(error instanceof ConvexError)) return null
    const data: unknown = error.data
    if (
        typeof data === 'object' &&
        data !== null &&
        'kind' in data &&
        data.kind === AGENT_TOOL_ERROR &&
        'message' in data &&
        typeof data.message === 'string'
    ) {
        return {
            kind: AGENT_TOOL_ERROR,
            reason: 'invalid_args',
            message: data.message,
        }
    }
    return null
}
