import { v } from 'convex/values'
import { query } from '../../_generated/server'
import { requireAuth } from '../../users/helpers'

/**
 * The rule one movement belongs to, plus where the series currently reaches —
 * or `null` when the movement is a one-off.
 *
 * `recurrenceId` is a client-generated string rather than a document id, so a
 * movement that references a rule the user has since deleted resolves to
 * `null` instead of throwing — the movement itself is still perfectly valid.
 *
 * `count` and `coveredThroughMs` are read off the last occurrence, in one
 * document read: indices run contiguously from 0, so the highest index *is*
 * the count, and no row has to be counted. Neither is stored on the rule, on
 * purpose — the rows are the truth about how far a series got
 * (docs/recurrency-design.md §5.2).
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

        const last = await ctx.db
            .query('transactions')
            .withIndex('by_user_recurrence_index', (q) =>
                q.eq('userId', userId).eq('recurrenceId', recurrenceId),
            )
            .order('desc')
            .first()
        const lastIndex =
            last?.recurrenceIndex === undefined
                ? null
                : Number(last.recurrenceIndex)

        return {
            id: rule.id,
            frequency: rule.frequency,
            dayInterval: rule.dayInterval,
            anchorDate: rule.anchorDate,
            endDate: rule.endDate,
            /** Occurrences that exist. Zero only while the series is empty. */
            count: lastIndex === null ? 0 : lastIndex + 1,
            /** The date of the last occurrence, i.e. how far the series goes. */
            coveredThroughMs: lastIndex === null ? null : (last?.date ?? null),
        }
    },
})
