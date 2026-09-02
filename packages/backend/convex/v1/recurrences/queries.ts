import { v } from 'convex/values'
import { query } from '../../_generated/server'
import { requireAuth } from '../../users/helpers'

/**
 * The rule one movement belongs to, or `null` when it is a one-off.
 *
 * `recurrenceId` is a client-generated string rather than a document id, so a
 * movement that references a rule the user has since deleted resolves to
 * `null` instead of throwing — the movement itself is still perfectly valid.
 */
export const get = query({
    args: { recurrenceId: v.optional(v.string()) },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const recurrenceId = args.recurrenceId
        if (!recurrenceId) return null

        const rule = await ctx.db
            .query('recurrences')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', recurrenceId),
            )
            .unique()
        if (!rule || rule.isArchived) return null

        return {
            id: rule.id,
            frequency: rule.frequency,
            dayInterval: rule.dayInterval,
            anchorDate: rule.anchorDate,
            endDate: rule.endDate,
        }
    },
})
