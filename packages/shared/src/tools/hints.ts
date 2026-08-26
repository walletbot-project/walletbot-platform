// Static per-tool hints appended to successful tool results.
//
// The system prompt carries the suggestion rules, but a rule read at connect
// time competes with everything else in the prompt by the time it matters. A
// hint rides on a result the model just asked for, so it lands in the same
// turn as the decision it informs. Nothing here tracks state or counts calls:
// the hint only asks the model to CHECK, and the model decides from the
// conversation it already has whether the moment fits.
//
// Keep them short and keep them checks, never orders. The detail lives in the
// `suggesting-features` skill; these point at it.
//
// Applied at the single dispatch point on each client, so a tool never has to
// remember to carry its own hint:
//   web    — executeToolCall (apps/web/src/lib/agent-tools/index.ts)
//   native — ToolExecutors.execute (apps/native/lib/voice/tool_executors.dart,
//            reading kAgentToolHints from the codegen)

import type { toolSchemas } from './definitions'

type ToolName = keyof typeof toolSchemas

export const TOOL_HINTS: Partial<Record<ToolName, string>> = {
    summarizeTransactions:
        'If the user has asked for this number before, a home dashboard widget keeps it on their home screen. Consider offering once, in one sentence, after you answer. See the suggesting-features skill.',
    getAccountBalance:
        'If the user checks this balance often, a balance card shows it on their home screen without asking. Consider offering once, in one sentence, after you answer. See the suggesting-features skill.',
    createAccount:
        'The account already exists with a default color and icon. If one would make it easier to spot in a list, consider offering to set it now, in one sentence. Never ask before creating. See the suggesting-features skill.',
    createCategory:
        'Two things to check now that the category exists. A color or icon makes it easier to spot. And if the user is describing a context that cuts across categories (a trip, an office, a shared flat), a tag fits better than a category. See the suggesting-features skill.',
    createTag:
        'Tags nest: pass parentIdOrName to make one a subtag, and a filter on the parent covers every child. Tags take a color but no icon. Consider offering either once, after confirming. See the suggesting-features skill.',
}

/**
 * Attach the tool's hint to a successful result. Failures are left untouched:
 * a call that did not work is never the moment to pitch a feature (and the
 * error envelope is asserted verbatim by tests on both clients).
 */
export function withToolHint(
    name: string,
    result: Record<string, unknown>,
): Record<string, unknown> {
    if (result.ok !== true || 'hint' in result) return result
    const hint = TOOL_HINTS[name as ToolName]
    return hint ? { ...result, hint } : result
}
