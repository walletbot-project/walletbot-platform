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
        // When true, each returned transaction is enriched with its `tagIds`
        // (one indexed read per row). Off by default so the agent's list calls
        // stay cheap — only the activity view, which filters by tag, opts in.
        includeTags: v.optional(v.boolean()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const { dateFrom, dateTo } = args

        // Pick the narrowest index available given the filters. The date range
        // is folded into the index range wherever the chosen index carries the
        // `date` column (account, category, and the default date index) so
        // filtering by date stays index-backed — never a scan.
        const result = await (async () => {
            if (args.accountId) {
                const accId = args.accountId
                return await ctx.db
                    .query('transactions')
                    .withIndex('by_user_account_date', (q) => {
                        const base = q
                            .eq('userId', userId)
                            .eq('accountId', accId)
                        if (dateFrom !== undefined && dateTo !== undefined) {
                            return base
                                .gte('date', dateFrom)
                                .lte('date', dateTo)
                        }
                        if (dateFrom !== undefined) {
                            return base.gte('date', dateFrom)
                        }
                        if (dateTo !== undefined) {
                            return base.lte('date', dateTo)
                        }
                        return base
                    })
                    .order('desc')
                    .paginate(args.paginationOpts)
            }
            if (args.categoryId) {
                const catId = args.categoryId
                return await ctx.db
                    .query('transactions')
                    .withIndex('by_user_category_date', (q) => {
                        const base = q
                            .eq('userId', userId)
                            .eq('categoryId', catId)
                        if (dateFrom !== undefined && dateTo !== undefined) {
                            return base
                                .gte('date', dateFrom)
                                .lte('date', dateTo)
                        }
                        if (dateFrom !== undefined) {
                            return base.gte('date', dateFrom)
                        }
                        if (dateTo !== undefined) {
                            return base.lte('date', dateTo)
                        }
                        return base
                    })
                    .order('desc')
                    .paginate(args.paginationOpts)
            }
            if (args.type) {
                return await ctx.db
                    .query('transactions')
                    .withIndex('by_user_type', (q) =>
                        q
                            .eq('userId', userId)
                            .eq(
                                'type',
                                args.type as Doc<'transactions'>['type'],
                            ),
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
                .withIndex('by_user_date', (q) => {
                    const base = q.eq('userId', userId)
                    if (dateFrom !== undefined && dateTo !== undefined) {
                        return base.gte('date', dateFrom).lte('date', dateTo)
                    }
                    if (dateFrom !== undefined) {
                        return base.gte('date', dateFrom)
                    }
                    if (dateTo !== undefined) {
                        return base.lte('date', dateTo)
                    }
                    return base
                })
                .order('desc')
                .paginate(args.paginationOpts)
        })()

        // Uniform return shape (page items carry an optional `tagIds`) so the
        // type doesn't fork on `includeTags`. Tag joins run only when opted in.
        const page = await Promise.all(
            result.page.map(
                async (
                    txn,
                ): Promise<Doc<'transactions'> & { tagIds?: string[] }> => {
                    if (!args.includeTags) return txn
                    const joins = await ctx.db
                        .query('transactionTags')
                        .withIndex('by_user_transaction', (q) =>
                            q.eq('userId', userId).eq('transactionId', txn.id),
                        )
                        .collect()
                    return { ...txn, tagIds: joins.map((j) => j.tagId) }
                },
            ),
        )
        return { ...result, page }
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
