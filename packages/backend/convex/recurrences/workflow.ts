import { WorkflowManager } from '@convex-dev/workflow'
import { v } from 'convex/values'
import { components, internal } from '../_generated/api'
import { occurrencePatch } from '../transactions/helpers'

export const workflow = new WorkflowManager(components.workflow)

/**
 * Materialises a range of a recurring rule's occurrences, one batch per step.
 *
 * A rule with no end date can be 500 movements; they are ordinary transactions
 * (docs/recurrency-design.md §2.5), so this is 500 inserts plus their
 * aggregate updates. One mutation would not survive that. Each step is a
 * separate transaction the workflow can retry on its own, and
 * `materializeBatch` only fills gaps, so a retry never duplicates.
 *
 * `from`/`to` are resolved by the caller and carried unchanged, so a top-up
 * extends the series exactly once no matter how the run is retried.
 *
 * Only the web path runs this. Native materialises locally — it has to work
 * offline — and pushes the rows up, so generating them here as well would
 * double the series.
 */
export const materializeRecurrence = workflow.define({
    args: {
        userId: v.string(),
        recurrenceId: v.string(),
        from: v.number(),
        to: v.number(),
    },
    handler: async (step, args): Promise<number> => {
        let from = args.from
        while (from < args.to) {
            const result = await step.runMutation(
                internal.recurrences.internal.materializeBatch,
                {
                    userId: args.userId,
                    recurrenceId: args.recurrenceId,
                    from,
                    to: args.to,
                },
            )
            if (result.done) return result.next
            from = result.next
        }
        return from
    },
})

/**
 * Carries an edit down a series' tail, one batch per step.
 *
 * Same reason as materialising: "this and the ones after it" on a daily rule
 * is up to 500 rows plus their aggregate entries, which is not one mutation's
 * worth of work. Each step is retryable on its own, and re-patching an
 * occurrence with the same values is harmless.
 */
export const updateFutureOccurrences = workflow.define({
    args: {
        userId: v.string(),
        recurrenceId: v.string(),
        fromIndex: v.number(),
        patch: occurrencePatch,
    },
    handler: async (step, args): Promise<number> => {
        let fromIndex = args.fromIndex
        for (;;) {
            const result = await step.runMutation(
                internal.recurrences.internal.updateFutureBatch,
                {
                    userId: args.userId,
                    recurrenceId: args.recurrenceId,
                    fromIndex,
                    patch: args.patch,
                },
            )
            if (result.done) return result.next
            fromIndex = result.next
        }
    },
})

/**
 * Archives a series' tail, one batch per step. Idempotent: an occurrence that
 * is already archived is skipped, so a retried step never double-tombstones.
 */
export const archiveFutureOccurrences = workflow.define({
    args: {
        userId: v.string(),
        recurrenceId: v.string(),
        fromIndex: v.number(),
    },
    handler: async (step, args): Promise<number> => {
        let fromIndex = args.fromIndex
        for (;;) {
            const result = await step.runMutation(
                internal.recurrences.internal.archiveFutureBatch,
                {
                    userId: args.userId,
                    recurrenceId: args.recurrenceId,
                    fromIndex,
                },
            )
            if (result.done) return result.next
            fromIndex = result.next
        }
    },
})
