import { paginationOptsValidator } from 'convex/server'
import { v } from 'convex/values'
import type { Doc } from '../_generated/dataModel'
import type { QueryCtx } from '../_generated/server'
import { query } from '../_generated/server'
import {
    accountNamespace,
    inflowsByAccount,
    outflowsByAccount,
} from '../aggregates'
import { requireAuth } from '../users/helpers'

// Bounded read so we never accidentally collect an unbounded set. Callers that
// truly need everything must paginate via `listPaginated`.
const MAX_RECENT = 100

export const get = query({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const txn = await ctx.db
            .query('transactions')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (!txn) return null

        const joins = await ctx.db
            .query('transactionTags')
            .withIndex('by_user_transaction', (q) =>
                q.eq('userId', userId).eq('transactionId', txn.id),
            )
            .collect()
        return { ...txn, tagIds: joins.map((j) => j.tagId) }
    },
})

export const recent = query({
    args: { limit: v.optional(v.number()) },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const limit = Math.min(args.limit ?? 10, MAX_RECENT)
        return await ctx.db
            .query('transactions')
            .withIndex('by_user_date', (q) => q.eq('userId', userId))
            .order('desc')
            .take(limit)
    },
})

export const listPaginated = query({
    args: {
        paginationOpts: paginationOptsValidator,
        type: v.optional(
            v.union(
                v.literal('expense'),
                v.literal('income'),
                v.literal('transfer'),
                v.literal('balance_adjustment'),
            ),
        ),
        accountId: v.optional(v.string()),
        categoryId: v.optional(v.string()),
        status: v.optional(v.union(v.literal('pending'), v.literal('cleared'))),
        dateFrom: v.optional(v.int64()),
        dateTo: v.optional(v.int64()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)

        // Pick the narrowest index available given the filters.
        if (args.accountId) {
            return await ctx.db
                .query('transactions')
                .withIndex('by_user_account_date', (q) => {
                    const accId = args.accountId as string
                    if (
                        args.dateFrom !== undefined &&
                        args.dateTo !== undefined
                    ) {
                        return q
                            .eq('userId', userId)
                            .eq('accountId', accId)
                            .gte('date', args.dateFrom)
                            .lte('date', args.dateTo)
                    }
                    if (args.dateFrom !== undefined) {
                        return q
                            .eq('userId', userId)
                            .eq('accountId', accId)
                            .gte('date', args.dateFrom)
                    }
                    if (args.dateTo !== undefined) {
                        return q
                            .eq('userId', userId)
                            .eq('accountId', accId)
                            .lte('date', args.dateTo)
                    }
                    return q.eq('userId', userId).eq('accountId', accId)
                })
                .order('desc')
                .paginate(args.paginationOpts)
        }
        if (args.categoryId) {
            return await ctx.db
                .query('transactions')
                .withIndex('by_user_category_date', (q) =>
                    q
                        .eq('userId', userId)
                        .eq('categoryId', args.categoryId as string),
                )
                .order('desc')
                .paginate(args.paginationOpts)
        }
        if (args.type) {
            return await ctx.db
                .query('transactions')
                .withIndex('by_user_type', (q) =>
                    q
                        .eq('userId', userId)
                        .eq('type', args.type as Doc<'transactions'>['type']),
                )
                .order('desc')
                .paginate(args.paginationOpts)
        }
        if (args.status) {
            return await ctx.db
                .query('transactions')
                .withIndex('by_user_status', (q) =>
                    q
                        .eq('userId', userId)
                        .eq('status', args.status as 'pending' | 'cleared'),
                )
                .order('desc')
                .paginate(args.paginationOpts)
        }
        return await ctx.db
            .query('transactions')
            .withIndex('by_user_date', (q) => q.eq('userId', userId))
            .order('desc')
            .paginate(args.paginationOpts)
    },
})

// O(log n) balance read backed by two TableAggregates over `transactions`.
// See aggregates.ts for the namespace/sumValue contracts.
export async function computeAccountBalance(
    ctx: QueryCtx,
    userId: string,
    accountId: string,
): Promise<bigint> {
    const namespace = accountNamespace(userId, accountId)
    const [outflows, inflows] = await Promise.all([
        outflowsByAccount.sum(ctx, { namespace }),
        inflowsByAccount.sum(ctx, { namespace }),
    ])
    return BigInt(Math.round(outflows + inflows))
}

export const balance = query({
    args: { accountId: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const account = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.accountId),
            )
            .unique()
        if (!account) return null
        const balanceCents = await computeAccountBalance(
            ctx,
            userId,
            args.accountId,
        )
        return { balance: balanceCents, currency: account.currency }
    },
})
