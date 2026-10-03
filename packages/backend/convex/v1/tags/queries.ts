import { compareByPositionThenName } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { query } from '../../_generated/server'
import { resolveOccurrenceCutoff } from '../../occurrences/helpers'
import { countTaggedBefore } from '../../tags/helpers'
import { requireAuth } from '../../users/helpers'

// Flat lists are strictly alphabetical: forms and pickers show tags by name,
// ignoring the user's tree order (which only `listActiveWithCounts` carries).
const byName = (a: { name: string }, b: { name: string }) =>
    a.name.localeCompare(b.name, undefined, { sensitivity: 'base' })

export const listActive = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        const rows = await ctx.db
            .query('tags')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .collect()
        return rows.sort(byName)
    },
})

export const list = query({
    args: { includeArchived: v.optional(v.boolean()) },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const rows = args.includeArchived
            ? await ctx.db
                  .query('tags')
                  .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                  .collect()
            : await ctx.db
                  .query('tags')
                  .withIndex('by_user_archived', (q) =>
                      q.eq('userId', userId).eq('isArchived', false),
                  )
                  .collect()
        return rows.sort(byName)
    },
})

export const listActiveWithCounts = query({
    args: { asOfMs: v.optional(v.int64()) },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const asOfMs = resolveOccurrenceCutoff(args.asOfMs)
        const tags = await ctx.db
            .query('tags')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .collect()

        const withCounts = await Promise.all(
            tags.map(async (tag) => ({
                ...tag,
                transactionCount: await countTaggedBefore(
                    ctx,
                    userId,
                    tag.id,
                    asOfMs,
                ),
            })),
        )

        // The tag tree's order: the client groups siblings by `parentId`
        // and keeps this relative order inside each level.
        return withCounts.sort(compareByPositionThenName)
    },
})

export const get = query({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        return await ctx.db
            .query('tags')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
    },
})

// Total expense spend for a tag within [fromMs, toExclusiveMs), grouped by
// currency and sorted desc. Backs the "gastado este mes" hero in the tag
// details sheet. Walks the tag's join rows (bounded by its usage) and reads
// each tagged transaction by its indexed id.
export const spendByCurrency = query({
    args: {
        id: v.string(),
        fromMs: v.int64(),
        toExclusiveMs: v.int64(),
        asOfMs: v.optional(v.int64()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const asOfMs = resolveOccurrenceCutoff(args.asOfMs)
        const joins = await ctx.db
            .query('transactionTags')
            .withIndex('by_user_tag', (q) =>
                q.eq('userId', userId).eq('tagId', args.id),
            )
            .collect()

        const totals = new Map<string, number>()
        for (const join of joins) {
            const t = await ctx.db
                .query('transactions')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', join.transactionId),
                )
                .unique()
            if (!t || t.isArchived || t.type !== 'expense') continue
            if (t.date < args.fromMs || t.date >= args.toExclusiveMs) continue
            if (t.date >= asOfMs) continue
            const cents = Math.abs(Number(t.amount))
            totals.set(t.currency, (totals.get(t.currency) ?? 0) + cents)
        }
        return [...totals.entries()]
            .map(([currency, cents]) => ({ currency, cents }))
            .sort((a, b) => b.cents - a.cents)
    },
})

// The most recent (non-archived) transactions carrying a tag, newest first.
// Backs the "últimos movimientos" section of the tag details sheet.
export const recentTransactions = query({
    args: {
        id: v.string(),
        limit: v.optional(v.number()),
        asOfMs: v.optional(v.int64()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const asOfMs = resolveOccurrenceCutoff(args.asOfMs)
        const limit = Math.min(args.limit ?? 5, 50)
        const joins = await ctx.db
            .query('transactionTags')
            .withIndex('by_user_tag', (q) =>
                q.eq('userId', userId).eq('tagId', args.id),
            )
            .collect()

        const txns = []
        for (const join of joins) {
            const t = await ctx.db
                .query('transactions')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', join.transactionId),
                )
                .unique()
            if (t && !t.isArchived && t.date < asOfMs) txns.push(t)
        }
        txns.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0))
        return txns.slice(0, limit)
    },
})
