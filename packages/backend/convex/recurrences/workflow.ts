import { WorkflowManager } from '@convex-dev/workflow'
import { v } from 'convex/values'
import { components, internal } from '../_generated/api'

export const workflow = new WorkflowManager(components.workflow)

/**
 * Materialises a recurring rule's occurrences, one batch per step.
 *
 * A rule with no end date can be 500 movements; they are ordinary transactions
 * (docs/recurrency-design.md §2.5), so this is 500 inserts plus their
 * aggregate updates. One mutation would not survive that. Each step is a
 * separate transaction the workflow can retry on its own, and
 * `materializeBatch` only fills gaps, so a retry never duplicates.
 *
 * Only the web path runs this. Native materialises locally — it has to work
 * offline — and pushes the rows up, so generating them here as well would
 * double the series.
 */
export const materializeRecurrence = workflow.define({
    args: { userId: v.string(), recurrenceId: v.string() },
    handler: async (step, args): Promise<number> => {
        let from = 1 // Occurrence 0 is the transaction the user just created.
        for (;;) {
            const result = await step.runMutation(
                internal.recurrences.internal.materializeBatch,
                { userId: args.userId, recurrenceId: args.recurrenceId, from },
            )
            if (result.done) return result.next
            from = result.next
        }
    },
})
