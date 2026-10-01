import { v } from 'convex/values'
import { internal } from '../_generated/api'
import { internalMutation } from '../_generated/server'
import { transactionsByTag } from '../aggregates'
import { tagAggregateAttach } from './helpers'

// One-time idempotent backfill that seeds `transactionsByTag` from existing
// `transactionTags` rows. Safe to run multiple times. Run once after the
// deploy that registers the component:
//   npx convex run tags/backfill:run
// Re-schedules itself until done.
const BATCH = 256

export const run = internalMutation({
    args: { cursor: v.optional(v.union(v.string(), v.null())) },
    handler: async (ctx, args) => {
        const page = await ctx.db
            .query('transactionTags')
            .paginate({ numItems: BATCH, cursor: args.cursor ?? null })

        for (const join of page.page) {
            await tagAggregateAttach(ctx, join)
        }

        if (!page.isDone) {
            await ctx.scheduler.runAfter(0, internal.tags.backfill.run, {
                cursor: page.continueCursor,
            })
        }
        return {
            processed: page.page.length,
            isDone: page.isDone,
            nextCursor: page.continueCursor,
        }
    },
})

// Clear the aggregate entirely. Use only when you're about to re-backfill.
export const clear = internalMutation({
    args: {},
    handler: async (ctx) => {
        await transactionsByTag.clearAll(ctx)
    },
})
