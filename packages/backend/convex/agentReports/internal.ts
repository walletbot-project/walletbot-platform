import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'

/**
 * Drops reports past their retention window.
 *
 * A report holds excerpts of a conversation, so it inherits the twelve-month
 * ceiling the privacy policy already sets for voice history — keeping the
 * moderation copy longer than the transcript it was cut from would be a promise
 * the policy doesn't make.
 *
 * Walks `by_createdAt` oldest-first in `limit`-sized batches, never a full scan.
 */
export const deleteOldReports = internalMutation({
    args: { olderThanMs: v.number(), limit: v.number() },
    handler: async (ctx, args) => {
        const cutoff = BigInt(Date.now() - args.olderThanMs)
        const rows = await ctx.db
            .query('agentReports')
            .withIndex('by_createdAt', (q) => q.lt('createdAt', cutoff))
            .order('asc')
            .take(args.limit)

        for (const row of rows) {
            await ctx.db.delete(row._id)
        }
        return { deleted: rows.length }
    },
})
