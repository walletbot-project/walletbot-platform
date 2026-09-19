import { SERIES_COUNT_CAP } from '@wallet-bot/shared'
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
 * `total`, `position` and `coveredThroughMs` are derived from the occurrence
 * rows (at most `SERIES_COUNT_CAP + 1` reads, `null` beyond the cap). None is
 * stored on the rule, on purpose — the rows are the truth about how far a
 * series got (docs/recurrency-design.md §5.2).
 */
export const get = query({
    args: {
        recurrenceId: v.optional(v.string()),
        /** The occurrence being looked at, so its position can be counted. */
        occurrenceIndex: v.optional(v.int64()),
    },
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

        // The series newest-slot-first, one more than the cap so "did it fit?"
        // is answerable. Read unfiltered and filtered here, so the cost is
        // exactly `SERIES_COUNT_CAP + 1` documents rather than however many
        // archived ones a filtered `.take()` would have had to walk past.
        const slots = await ctx.db
            .query('transactions')
            .withIndex('by_user_recurrence_index', (q) =>
                q.eq('userId', userId).eq('recurrenceId', recurrenceId),
            )
            .order('desc')
            .take(SERIES_COUNT_CAP + 1)
        const counted = slots.length <= SERIES_COUNT_CAP
        const living = slots.filter((row) => !row.isArchived)
        const occurrenceIndex = args.occurrenceIndex

        // Position and total count the occurrences that *survive*. They are
        // deliberately not `recurrenceIndex + 1` and `maxIndex + 1`: a deleted
        // occurrence keeps its index, because that index is the key its date
        // is projected from and the marker that stops the materialiser
        // recreating it. So the index counts slots, and the user counts
        // movements.
        const total = counted ? living.length : null
        const position =
            counted && occurrenceIndex !== undefined
                ? living.filter(
                      (row) => (row.recurrenceIndex ?? 0n) <= occurrenceIndex,
                  ).length
                : null

        return {
            id: rule.id,
            frequency: rule.frequency,
            dayInterval: rule.dayInterval,
            anchorDate: rule.anchorDate,
            endDate: rule.endDate,
            /** Surviving occurrences, or null when the series is past the cap. */
            total,
            /** This occurrence's rank among the survivors. */
            position,
            /** The date of the last surviving occurrence — how far it goes. */
            coveredThroughMs: living[0]?.date ?? null,
        }
    },
})

/** How many rules one `list` returns. Rules are few by nature. */
const RULE_LIST_CAP = 50

/**
 * The user's recurring rules, with the movement each one creates and how far
 * its series reaches.
 *
 * Two indexed reads per rule (the anchor for the name and amount, the last
 * occurrence for the reach) rather than the capped survivor count `get` does:
 * a list answers "what repeats?", and the position of a specific occurrence is
 * a question about that occurrence.
 */
export const list = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        const rules = await ctx.db
            .query('recurrences')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .take(RULE_LIST_CAP)

        const items = []
        for (const rule of rules) {
            const anchor = await ctx.db
                .query('transactions')
                .withIndex('by_user_recurrence_index', (q) =>
                    q
                        .eq('userId', userId)
                        .eq('recurrenceId', rule.id)
                        .eq('recurrenceIndex', 0n),
                )
                .first()
            const last = await ctx.db
                .query('transactions')
                .withIndex('by_user_recurrence_index', (q) =>
                    q.eq('userId', userId).eq('recurrenceId', rule.id),
                )
                .order('desc')
                .first()
            items.push({
                id: rule.id,
                name: anchor?.name ?? null,
                type: anchor?.type ?? null,
                amount: anchor?.amount ?? null,
                currency: anchor?.currency ?? null,
                accountId: anchor?.accountId ?? null,
                categoryId: anchor?.categoryId ?? null,
                frequency: rule.frequency,
                dayInterval: rule.dayInterval,
                anchorDate: rule.anchorDate,
                endDate: rule.endDate,
                coveredThroughMs: last?.date ?? null,
            })
        }
        return items
    },
})
