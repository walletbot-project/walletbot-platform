import { type FilterGroup, isFilterGroup } from '@wallet-bot/shared'
import type { PaginationOptions, PaginationResult } from 'convex/server'
import { paginationOptsValidator } from 'convex/server'
import { v } from 'convex/values'
import { stream } from 'convex-helpers/server/stream'
import type { Doc, Id } from '../../_generated/dataModel'
import type { QueryCtx } from '../../_generated/server'
import { query } from '../../_generated/server'
import {
    accountNamespace,
    inflowsByAccount,
    outflowsByAccount,
} from '../../aggregates'
import schema from '../../schema'
import { requireAuth } from '../../users/helpers'
import {
    boundByDate,
    buildEvaluationContext,
    filterFromConfig,
    indexDateWindow,
    MAX_SCAN,
    matchesNode,
} from '../dashboard/helpers'

// Bounded read so we never accidentally collect an unbounded set. Callers that
// truly need everything must paginate via `listPaginated`.
const MAX_RECENT = 100

/**
 * Rows pulled from each text index before the rest of the tree is applied.
 * Text search is the one dimension no `date`/`account`/`category` index can
 * bound, so the search index supplies the candidates and the predicate narrows
 * them; this caps how many it may supply per index.
 */
const MAX_SEARCH_CANDIDATES = 512

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

/**
 * The activity list, filtered by a canonical filter tree
 * (`packages/shared/src/dashboard/filter.ts`) instead of the handful of
 * dimensions `listPaginated` can express.
 *
 * Native filters in SQL over its whole local database, so every dimension is
 * applied to every row it owns. This is the server-side equivalent: the same
 * evaluator the dashboard widgets use (`matchesNode`), applied to an
 * index-bounded stream, with pagination happening *after* the predicate so a
 * page is a page of matches rather than a page of candidates. Filtering the
 * already-loaded page in the browser — what the web activity screen did — could
 * only ever see the rows it had paged in.
 */
export const listByFilter = query({
    args: {
        paginationOpts: paginationOptsValidator,
        /** Canonical filter JSON, i.e. `filterConfigToJson(filter)`. */
        config: v.string(),
    },
    handler: async (
        ctx,
        args,
    ): Promise<PaginationResult<Doc<'transactions'>>> => {
        const userId = await requireAuth(ctx)
        const { filter, root } = filterFromConfig(args.config)
        const now = new Date()
        const evaluation = await buildEvaluationContext(ctx, userId, root, now)
        const matches = async (txn: Doc<'transactions'>) =>
            !txn.isArchived && matchesNode(txn, root, evaluation)

        const window = indexDateWindow(filter, root, now)
        const anchorAccount =
            filter.accountIds.length === 1 ? filter.accountIds[0] : null
        const anchorCategory =
            filter.categoryIds.length === 1 ? filter.categoryIds[0] : null

        // Text is the one dimension no ordered index can bound — but the search
        // index only offers a bounded slice of best matches, while an ordered
        // scan pages through *every* row in its range. So the search index is
        // the fallback, taken only when nothing else can bound the read: with a
        // date window or a single account/category to anchor on, the ordered
        // scan is used and text is evaluated row by row, which is complete.
        const canAnchorOnIndex =
            window !== null || anchorAccount !== null || anchorCategory !== null
        const needle = canAnchorOnIndex ? null : searchAnchor(root)
        if (needle !== null) {
            return await paginateSearchMatches(
                ctx,
                userId,
                needle,
                matches,
                args.paginationOpts,
            )
        }

        const table = stream(ctx.db, schema).query('transactions')

        // The narrowest index the filter's anchor dimensions allow, date window
        // folded into the range. `either` gets no account anchor: the account
        // can sit on either leg, and each leg is its own index — the predicate
        // enforces the dimension in that case rather than a merged read.
        const anchored =
            anchorAccount !== null && filter.accountDirection === 'source'
                ? table.withIndex('by_user_account_date', (q) =>
                      boundByDate(
                          q.eq('userId', userId).eq('accountId', anchorAccount),
                          window,
                      ),
                  )
                : anchorAccount !== null &&
                    filter.accountDirection === 'destination'
                  ? table.withIndex('by_user_to_account_date', (q) =>
                        boundByDate(
                            q
                                .eq('userId', userId)
                                .eq('toAccountId', anchorAccount),
                            window,
                        ),
                    )
                  : anchorCategory !== null
                    ? table.withIndex('by_user_category_date', (q) =>
                          boundByDate(
                              q
                                  .eq('userId', userId)
                                  .eq('categoryId', anchorCategory),
                              window,
                          ),
                      )
                    : table.withIndex('by_user_date', (q) =>
                          boundByDate(q.eq('userId', userId), window),
                      )

        return await anchored
            .order('desc')
            .filterWith(matches)
            // Pre-filter pagination reads until the page is full, so the cap is
            // what stops a filter matching almost nothing from walking the
            // whole table in one call.
            .paginate({ ...args.paginationOpts, maximumRowsRead: MAX_SCAN })
    },
})

/**
 * The text a search index may drive the read with: a `contains` condition
 * directly under a plain top-level `and`, where every match must satisfy it.
 * An `or` root, a negated one, or `not contains` constrains nothing on its own,
 * so those keep the ordered-index path and evaluate text row by row.
 */
function searchAnchor(root: FilterGroup): string | null {
    if (root.combinator !== 'and' || root.not === true) return null
    for (const child of root.children) {
        if (isFilterGroup(child)) continue
        if (child.field !== 'text' || child.operator !== 'contains') continue
        if (typeof child.value !== 'string') continue
        const needle = child.value.trim()
        if (needle) return needle
    }
    return null
}

/**
 * Search-anchored page: union the candidates both text indexes offer, apply the
 * whole tree to them, then order and page in memory.
 *
 * The candidates are word-prefix matches (what a search index gives); the
 * predicate then re-applies the substring test every other evaluator uses, so
 * what comes back is exactly what native's `LIKE '%needle%'` would return, with
 * two bounds native does not have: an infix like "bucks" inside "Starbucks" is
 * never offered as a candidate, and only the best `MAX_SEARCH_CANDIDATES` per
 * index are considered. Both are the price of reaching the user's whole history
 * instead of the rows the browser happened to have paged in.
 */
async function paginateSearchMatches(
    ctx: QueryCtx,
    userId: string,
    needle: string,
    matches: (txn: Doc<'transactions'>) => Promise<boolean>,
    paginationOpts: PaginationOptions,
): Promise<PaginationResult<Doc<'transactions'>>> {
    const [byName, byDescription] = await Promise.all([
        ctx.db
            .query('transactions')
            .withSearchIndex('search_name', (q) =>
                q
                    .search('name', needle)
                    .eq('userId', userId)
                    .eq('isArchived', false),
            )
            .take(MAX_SEARCH_CANDIDATES),
        ctx.db
            .query('transactions')
            .withSearchIndex('search_description', (q) =>
                q
                    .search('description', needle)
                    .eq('userId', userId)
                    .eq('isArchived', false),
            )
            .take(MAX_SEARCH_CANDIDATES),
    ])

    const candidates = new Map<Id<'transactions'>, Doc<'transactions'>>()
    for (const txn of [...byName, ...byDescription]) {
        candidates.set(txn._id, txn)
    }

    const matched: Doc<'transactions'>[] = []
    for (const txn of candidates.values()) {
        if (await matches(txn)) matched.push(txn)
    }
    matched.sort(newestFirst)

    // The candidate list is bounded and fully in hand, so the cursor is simply
    // how far into it the client has read. `endCursor`, when the client sends
    // one back, pins a page it already holds so live updates can't reshuffle it.
    const from = cursorOffset(paginationOpts.cursor, 0)
    const to = cursorOffset(
        paginationOpts.endCursor ?? null,
        from + paginationOpts.numItems,
    )
    const page = matched.slice(from, to)
    const continueCursor = String(from + page.length)
    return {
        page,
        isDone: from + page.length >= matched.length,
        continueCursor,
    }
}

function cursorOffset(cursor: string | null, fallback: number): number {
    if (cursor === null) return fallback
    const parsed = Number.parseInt(cursor, 10)
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback
}

/**
 * The activity ordering, matching the client's own list build and native's
 * `_buildListEntries`: newest date first, then newest creation, then id.
 */
function newestFirst(a: Doc<'transactions'>, b: Doc<'transactions'>): number {
    if (a.date !== b.date) return a.date > b.date ? -1 : 1
    if (a.createdAt !== b.createdAt) return a.createdAt > b.createdAt ? -1 : 1
    if (a.id === b.id) return 0
    return a.id > b.id ? -1 : 1
}

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

// Signed effect of a transaction on `accountId`'s running balance. Mirrors the
// native ledger replay (`_accountDelta`) and the aggregate sum contracts: a
// transaction touches the account either as source (`accountId`) or, for
// transfers, as destination (`toAccountId`) — never both. Archived rows are 0.
function accountDelta(txn: Doc<'transactions'>, accountId: string): bigint {
    if (txn.isArchived) return 0n
    let delta = 0n
    if (txn.accountId === accountId) {
        switch (txn.type) {
            case 'expense':
            case 'transfer':
                delta -= txn.amount
                break
            case 'income':
            case 'balance_adjustment':
                delta += txn.amount
                break
        }
    }
    if (txn.type === 'transfer' && txn.toAccountId === accountId) {
        delta += txn.toAmount ?? txn.amount
    }
    return delta
}

// Running balance of `accountId` immediately before and after the given
// transaction, matching the native ledger ordering (date, then createdAt, then
// client id). The bulk (everything strictly before the transaction's date) is
// an O(log n) aggregate sum; only rows sharing the exact same `date` are read
// to break ties around the target — that set is bounded to one millisecond on
// one account, so it stays tiny and index-backed.
export const balanceAroundTransaction = query({
    args: { transactionId: v.string(), accountId: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)

        const target = await ctx.db
            .query('transactions')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.transactionId),
            )
            .unique()
        if (!target || target.isArchived) return null

        const account = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.accountId),
            )
            .unique()
        if (!account) return null

        const date = target.date
        const namespace = accountNamespace(userId, args.accountId)

        // Everything on this account strictly before the target's date.
        const [outflows, inflows] = await Promise.all([
            outflowsByAccount.sum(ctx, {
                namespace,
                bounds: { upper: { key: date, inclusive: false } },
            }),
            inflowsByAccount.sum(ctx, {
                namespace,
                bounds: { upper: { key: date, inclusive: false } },
            }),
        ])
        let before = BigInt(Math.round(outflows + inflows))

        // Same-date rows touching the account, as source or transfer target.
        const [sourceRows, destRows] = await Promise.all([
            ctx.db
                .query('transactions')
                .withIndex('by_user_account_date', (q) =>
                    q
                        .eq('userId', userId)
                        .eq('accountId', args.accountId)
                        .eq('date', date),
                )
                .collect(),
            ctx.db
                .query('transactions')
                .withIndex('by_user_to_account_date', (q) =>
                    q
                        .eq('userId', userId)
                        .eq('toAccountId', args.accountId)
                        .eq('date', date),
                )
                .collect(),
        ])

        const sameDate = new Map<string, Doc<'transactions'>>()
        for (const row of [...sourceRows, ...destRows]) {
            if (!row.isArchived) sameDate.set(row.id, row)
        }
        const ordered = [...sameDate.values()].sort((a, b) => {
            if (a.createdAt !== b.createdAt)
                return a.createdAt < b.createdAt ? -1 : 1
            return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
        })

        let found = false
        for (const row of ordered) {
            if (row.id === target.id) {
                found = true
                break
            }
            before += accountDelta(row, args.accountId)
        }
        // The account doesn't participate in this transaction — nothing to show.
        if (!found) return null

        const after = before + accountDelta(target, args.accountId)
        return { before, after, currency: account.currency }
    },
})
