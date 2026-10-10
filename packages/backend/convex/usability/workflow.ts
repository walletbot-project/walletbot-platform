import { WorkflowManager } from '@convex-dev/workflow'
import { USABILITY_SCENARIOS } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { components, internal } from '../_generated/api'

export const workflow = new WorkflowManager(components.workflow)

/**
 * Creates a session's three test users and fills the scenario 0 and 2 ones
 * with their datasets. Every step is idempotent against the progress stored on
 * the session, so a failed run can simply be started again.
 */
export const provisionSession = workflow.define({
    args: { sessionId: v.id('usabilitySessions') },
    handler: async (step, { sessionId }): Promise<null> => {
        try {
            for (const scenario of USABILITY_SCENARIOS) {
                await step.runAction(
                    internal.usability.actions.createTestUser,
                    { sessionId, scenario },
                    { retry: true },
                )
            }
            await step.runMutation(internal.usability.internal.seedScenario0, {
                sessionId,
            })
            await step.runMutation(
                internal.usability.internal.seedScenario2Base,
                { sessionId },
            )
            for (;;) {
                const { done } = await step.runMutation(
                    internal.usability.internal.seedScenario2Batch,
                    { sessionId },
                )
                if (done) break
            }
            await step.runMutation(
                internal.usability.internal.finishProvisioning,
                { sessionId },
            )
        } catch (error) {
            await step.runMutation(internal.usability.internal.markFailed, {
                sessionId,
                error: error instanceof Error ? error.message : String(error),
            })
        }
        return null
    },
})
