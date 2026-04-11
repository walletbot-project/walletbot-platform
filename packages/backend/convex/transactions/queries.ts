import { paginationOptsValidator } from 'convex/server'
import { v } from 'convex/values'
import { query } from '../_generated/server'
import { requireAuth } from '../lib/auth'
import { transactionTypeValidator } from '../lib/validators'
import { computeAccountBalance } from './helpers'

export const listTransactions = query({
    args: {
        paginationOpts: paginationOptsValidator,
        type: v.optional(transactionTypeValidator),
        categoryId: v.optional(v.id('categories')),
        accountId: v.optional(v.id('accounts')),
        startDate: v.optional(v.string()),
        endDate: v.optional(v.string()),
        tagId: v.optional(v.id('tags')),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)

        // Pick the best index based on filters
        const buildQuery = () => {
            if (args.type) {
                return ctx.db
                    .query('transactions')
                    .withIndex('by_userId_and_type', (q) =>
                        q.eq('userId', user._id).eq('type', args.type!),
                    )
            }
            if (args.categoryId) {
                return ctx.db
                    .query('transactions')
                    .withIndex('by_userId_and_categoryId', (q) =>
                        q
                            .eq('userId', user._id)
                            .eq('categoryId', args.categoryId!),
                    )
            }
            if (args.accountId) {
                return ctx.db
                    .query('transactions')
                    .withIndex('by_userId_and_fromAccountId', (q) =>
                        q
                            .eq('userId', user._id)
                            .eq('fromAccountId', args.accountId!),
                    )
            }
            if (args.startDate || args.endDate) {
                const start = args.startDate ?? '2000-01-01'
                const end = args.endDate ?? '2099-12-31'
                return ctx.db
                    .query('transactions')
                    .withIndex('by_userId_and_date', (q) =>
                        q
                            .eq('userId', user._id)
                            .gte('date', start)
                            .lte('date', end),
                    )
            }
            return ctx.db
                .query('transactions')
                .withIndex('by_userId', (q) => q.eq('userId', user._id))
        }

        const result = await buildQuery()
            .order('desc')
            .paginate(args.paginationOpts)

        // Post-filter for tag (no index on array field)
        if (args.tagId) {
            return {
                ...result,
                page: result.page.filter((tx) => tx.tags.includes(args.tagId!)),
            }
        }

        return result
    },
})

export const getTransactionSummary = query({
    args: {
        startDate: v.optional(v.string()),
        endDate: v.optional(v.string()),
        displayCurrency: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)

        const start = args.startDate ?? '2000-01-01'
        const end = args.endDate ?? '2099-12-31'

        const transactions = await ctx.db
            .query('transactions')
            .withIndex('by_userId_and_date', (q) =>
                q.eq('userId', user._id).gte('date', start).lte('date', end),
            )
            .take(1000)

        let totalExpenseCents = 0
        let totalIncomeCents = 0
        const byCategory: Record<string, number> = {}

        for (const tx of transactions) {
            if (tx.type === 'expense') {
                totalExpenseCents += tx.amount
                const catKey = tx.categoryId ?? 'uncategorized'
                byCategory[catKey] = (byCategory[catKey] ?? 0) + tx.amount
            } else if (tx.type === 'income') {
                totalIncomeCents += tx.amount
            }
            // transfers don't affect totals
        }

        return {
            totalExpenseCents,
            totalIncomeCents,
            netFlowCents: totalIncomeCents - totalExpenseCents,
            count: transactions.length,
            byCategory: Object.entries(byCategory).map(
                ([categoryId, cents]) => ({
                    categoryId,
                    cents,
                }),
            ),
        }
    },
})

export const getAccountBalance = query({
    args: {
        accountId: v.id('accounts'),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        return await computeAccountBalance(ctx, user._id, args.accountId)
    },
})

export const getAllAccountBalances = query({
    args: {},
    handler: async (ctx) => {
        const user = await requireAuth(ctx)

        const accounts = await ctx.db
            .query('accounts')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .take(50)

        const balances = []
        for (const account of accounts) {
            const { balanceCents, currency } = await computeAccountBalance(
                ctx,
                user._id,
                account._id,
            )
            balances.push({
                accountId: account._id,
                name: account.name,
                type: account.type,
                icon: account.icon,
                balanceCents,
                currency,
            })
        }

        return balances
    },
})
