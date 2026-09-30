import { compareByPosition } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { query } from '../../_generated/server'
import { resolveOccurrenceCutoff } from '../../occurrences/helpers'
import { requireAuth } from '../../users/helpers'

// Every list of accounts comes back in the user's order (see
// `compareByPosition`), so forms and pickers show it without sorting again.
export const listActive = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        const rows = await ctx.db
            .query('accounts')
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
                  .query('accounts')
                  .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                  .collect()
            : await ctx.db
                  .query('accounts')
                  .withIndex('by_user_archived', (q) =>
                      q.eq('userId', userId).eq('isArchived', false),
                  )
                  .collect()
        return rows.sort(compareByPosition)
    },
})

export const get = query({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        return await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
    },
})

// The most recent (non-archived) transactions for an account, newest first.
// Backs the "últimas transacciones" section of the account details sheet.
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
            .withIndex('by_user_account_date', (q) =>
                q
                    .eq('userId', userId)
                    .eq('accountId', args.id)
                    .lt('date', asOfMs),
            )
            .order('desc')
            .filter((q) => q.eq(q.field('isArchived'), false))
            .take(limit)
    },
})
