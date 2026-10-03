import { compareByPosition } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { query } from '../../_generated/server'
import { resolveOccurrenceCutoff } from '../../occurrences/helpers'
import { requireAuth } from '../../users/helpers'

// Every list of categories comes back in the user's order (see
// `compareByPosition`), so forms and pickers show it without sorting again.
export const listActive = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        const rows = await ctx.db
            .query('categories')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .collect()
        return rows.sort(compareByPosition)
    },
})

export const list = query({
    args: { includeArchived: v.optional(v.boolean()) },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const rows = args.includeArchived
            ? await ctx.db
                  .query('categories')
                  .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                  .collect()
            : await ctx.db
                  .query('categories')
                  .withIndex('by_user_archived', (q) =>
                      q.eq('userId', userId).eq('isArchived', false),
                  )
                  .collect()
        return rows.sort(compareByPosition)
    },
})

export const listActiveWithCounts = query({
    args: { asOfMs: v.optional(v.int64()) },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const asOfMs = resolveOccurrenceCutoff(args.asOfMs)
        const categories = await ctx.db
            .query('categories')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .collect()

        const withCounts = await Promise.all(
            categories.map(async (category) => {
                // A movement that has not happened yet does not count
                // towards the category — the same cutoff Activity reads at.
                const txns = await ctx.db
                    .query('transactions')
                    .withIndex('by_user_category_date', (q) =>
                        q
                            .eq('userId', userId)
                            .eq('categoryId', category.id)
                            .lt('date', asOfMs),
                    )
                    .collect()
                return {
                    ...category,
                    transactionCount: txns.filter((t) => !t.isArchived).length,
                }
            }),
        )

        return withCounts.sort(compareByPosition)
    },
})

export const get = query({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        return await ctx.db
            .query('categories')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
    },
})

// Total expense spend for a category within [fromMs, toExclusiveMs), grouped by
// currency and sorted desc. Backs the "gastado este mes" hero in the category
// details sheet. Index-narrowed to one category + the date window, so it never
// scans the table.
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
        const txns = await ctx.db
            .query('transactions')
            .withIndex('by_user_category_date', (q) =>
                q
                    .eq('userId', userId)
                    .eq('categoryId', args.id)
                    .gte('date', args.fromMs)
                    .lt(
                        'date',
                        args.toExclusiveMs < asOfMs
                            ? args.toExclusiveMs
                            : asOfMs,
                    ),
            )
            .collect()

        const totals = new Map<string, number>()
        for (const t of txns) {
            if (t.isArchived || t.type !== 'expense') continue
            const cents = Math.abs(Number(t.amount))
            totals.set(t.currency, (totals.get(t.currency) ?? 0) + cents)
        }
        return [...totals.entries()]
            .map(([currency, cents]) => ({ currency, cents }))
            .sort((a, b) => b.cents - a.cents)
    },
})

// The most recent (non-archived) transactions in a category, newest first.
// Backs the "últimos movimientos" section of the category details sheet.
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
        return await ctx.db
            .query('transactions')
            .withIndex('by_user_category_date', (q) =>
                q
                    .eq('userId', userId)
                    .eq('categoryId', args.id)
                    .lt('date', asOfMs),
            )
            .order('desc')
            .filter((q) => q.eq(q.field('isArchived'), false))
            .take(limit)
    },
})
