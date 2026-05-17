import { v } from 'convex/values'
import { internal } from '../_generated/api'
import { internalMutation } from '../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../aggregates'

// One-time idempotent backfill that seeds the aggregates from existing
// `transactions` rows. Safe to run multiple times.
//
// Trigger from the dashboard or `npx convex run transactions/backfill:run`.
// Re-schedules itself in 100ms chunks until done.
const BATCH = 256

export const run = internalMutation({
    args: { cursor: v.optional(v.union(v.string(), v.null())) },
    handler: async (ctx, args) => {
        const page = await ctx.db
            .query('transactions')
            .paginate({ numItems: BATCH, cursor: args.cursor ?? null })

        for (const doc of page.page) {
            await outflowsByAccount.insertIfDoesNotExist(ctx, doc)
            await inflowsByAccount.insertIfDoesNotExist(ctx, doc)
        }

        if (!page.isDone) {
            await ctx.scheduler.runAfter(
                0,
                internal.transactions.backfill.run,
                { cursor: page.continueCursor },
            )
        }
        return {
            processed: page.page.length,
            isDone: page.isDone,
            nextCursor: page.continueCursor,
        }
    },
})

// Clear both aggregates entirely. Use only when you're about to re-backfill.
export const clear = internalMutation({
    args: {},
    handler: async (ctx) => {
        await outflowsByAccount.clearAll(ctx)
        await inflowsByAccount.clearAll(ctx)
    },
})
