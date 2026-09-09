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
    occurredWindow,
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

// Backs the agent's session snapshot of recent movements. Archived rows are
// excluded by the index prefix, not by a predicate: a deleted movement the
// agent still describes back to the user reads as the delete having failed.
export const recent = query({
    args: { limit: v.optional(v.number()), asOfMs: v.int64() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const limit = Math.min(args.limit ?? 10, MAX_RECENT)
        return await ctx.db
            .query('transactions')
            .withIndex('by_user_archived_date', (q) =>
                q
                    .eq('userId', userId)
                    .eq('isArchived', false)
                    .lt('date', args.asOfMs),
            )
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
        asOfMs: v.int64(),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        // The occurrence cutoff is just a tighter `dateTo`, so it rides the
        // same index range the caller's own date filter already uses.
        const { dateFrom } = args
        const lastOccurred = args.asOfMs - 1n
        const dateTo =
            args.dateTo === undefined
                ? lastOccurred
                : args.dateTo < lastOccurred
                  ? args.dateTo
                  : lastOccurred

        // What every branch below has to agree on, whatever index it picked:
        // an archived movement is never listed (it is a soft delete — the
        // agent describing one back to the user reads as the delete having
        // failed), and nothing at or past the occurrence cutoff has happened
        // yet. It is a predicate rather than an index range because none of
        // the five indexes carries `isArchived`, and two of them
        // (`by_user_type`, `by_user_status`) carry no `date` either, so those
        // branches have no way to bound either dimension. `maximumRowsRead`
        // below is what keeps a predicate-driven read bounded.
        const visible = async (txn: Doc<'transactions'>) =>
            !txn.isArchived &&
            txn.date <= dateTo &&
            (dateFrom === undefined || txn.date >= dateFrom)

        const table = stream(ctx.db, schema).query('transactions')

        // Pick the narrowest index available given the filters. The date range
        // is folded into the index range wherever the chosen index carries the
        // `date` column (account, category, and the default date index) so
        // filtering by date stays index-backed — never a scan.
        const scoped = (() => {
            if (args.accountId) {
                const accId = args.accountId
                return table.withIndex('by_user_account_date', (q) => {
                    const base = q.eq('userId', userId).eq('accountId', accId)
                    return dateFrom === undefined
                        ? base.lte('date', dateTo)
                        : base.gte('date', dateFrom).lte('date', dateTo)
                })
            }
            if (args.categoryId) {
                const catId = args.categoryId
                return table.withIndex('by_user_category_date', (q) => {
                    const base = q.eq('userId', userId).eq('categoryId', catId)
                    return dateFrom === undefined
                        ? base.lte('date', dateTo)
                        : base.gte('date', dateFrom).lte('date', dateTo)
                })
            }
            // Neither of the next two indexes carries `date`, so these are the
            // branches whose date bounds — the caller's and the occurrence
            // cutoff alike — exist only in `visible`.
            if (args.type) {
                return table.withIndex('by_user_type', (q) =>
                    q
                        .eq('userId', userId)
                        .eq('type', args.type as Doc<'transactions'>['type']),
                )
            }
            if (args.status) {
                return table.withIndex('by_user_status', (q) =>
                    q
                        .eq('userId', userId)
                        .eq('status', args.status as 'pending' | 'cleared'),
                )
            }
            // The unfiltered call, and the one the agent makes most. The only
            // branch whose index can pin `isArchived` outright, so every row
            // it yields is already a match.
            return table.withIndex('by_user_archived_date', (q) => {
                const base = q.eq('userId', userId).eq('isArchived', false)
                return dateFrom === undefined
                    ? base.lte('date', dateTo)
                    : base.gte('date', dateFrom).lte('date', dateTo)
            })
        })()

        const result = await scoped
            .order('desc')
            .filterWith(visible)
            // Pre-filter pagination reads until the page is full, so a page is
            // a page of matches rather than of candidates. Filtering the page
            // *after* `paginate` returned would be the other bug — pages that
            // arrive mostly empty while still promising more. The cap is what
            // stops a long run of archived rows from walking the whole range
            // in one call.
            .paginate({ ...args.paginationOpts, maximumRowsRead: MAX_SCAN })

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
 * The other side of the occurrence cutoff: the movements a recurring rule has
 * already materialised that have not happened yet.
 *
 * Ascending, unlike every other transaction list — these are upcoming, so the
 * nearest one belongs first. The rows are ordinary transactions; nothing about
 * them is a different kind of record, which is exactly why every read on the
 * other side of the cutoff has to exclude them.
 *
 * Archived rows are excluded by the index, not by a predicate over the page:
 * deleting the tail of a series archives hundreds of rows that keep their
 * dates, so filtering afterwards handed back pages that were mostly — or
 * entirely — empty while still reporting more to come.
 */
export const listUpcoming = query({
    args: {
        paginationOpts: paginationOptsValidator,
        asOfMs: v.int64(),
    },
    handler: async (
        ctx,
        args,
    ): Promise<PaginationResult<Doc<'transactions'>>> => {
        const userId = await requireAuth(ctx)
        return await ctx.db
            .query('transactions')
            .withIndex('by_user_archived_date', (q) =>
                q
                    .eq('userId', userId)
                    .eq('isArchived', false)
                    .gte('date', args.asOfMs),
            )
            .order('asc')
            .paginate(args.paginationOpts)
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
        asOfMs: v.int64(),
    },
    handler: async (
        ctx,
        args,
    ): Promise<PaginationResult<Doc<'transactions'>>> => {
        const userId = await requireAuth(ctx)
        const { filter, root } = filterFromConfig(args.config)
        const now = new Date()
        const evaluation = await buildEvaluationContext(
            ctx,
            userId,
            root,
            now,
            args.asOfMs,
        )
        const matches = async (txn: Doc<'transactions'>) =>
            !txn.isArchived && matchesNode(txn, root, evaluation)

        const window = occurredWindow(
            indexDateWindow(filter, root, now),
            args.asOfMs,
        )
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

/**
 * Server-side aggregation behind the agent's `summarizeTransactions` tool
 * (native computes the same thing locally over Drift — see
 * `SummaryRepository.byCategory` / `byAccount`, which this mirrors).
 *
 * Replaces the web executor's old client-side walk over `listPaginated`
 * (50 pages × 200 rows). The scan is bounded by the `by_user_date` index over
 * the requested window and capped at `MAX_SCAN` rows; `truncated` reports when
 * the cap cut the window short so the caller can say the totals are partial.
 *
 * Amounts are returned in cents (int64); callers convert to display units.
 */
export const summarize = query({
    args: {
        groupBy: v.union(v.literal('category'), v.literal('account')),
        dateFrom: v.int64(),
        dateTo: v.int64(),
        type: v.optional(
            v.union(
                v.literal('expense'),
                v.literal('income'),
                v.literal('transfer'),
            ),
        ),
        currency: v.optional(v.string()),
        asOfMs: v.int64(),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)

        const lastOccurred = args.asOfMs - 1n
        const dateTo = args.dateTo < lastOccurred ? args.dateTo : lastOccurred

        const stream = ctx.db
            .query('transactions')
            .withIndex('by_user_date', (q) =>
                q
                    .eq('userId', userId)
                    .gte('date', args.dateFrom)
                    .lte('date', dateTo),
            )
            .order('desc')

        let scanned = 0
        let truncated = false

        if (args.groupBy === 'category') {
            const totals = new Map<string, bigint>()
            for await (const t of stream) {
                scanned++
                if (scanned > MAX_SCAN) {
                    truncated = true
                    break
                }
                if (t.isArchived) continue
                if (args.type && t.type !== args.type) continue
                // Transfers move money between the user's own accounts, so
                // they never contribute to category totals (same rule as
                // native's SummaryRepository and the dashboard breakdowns).
                if (t.type === 'transfer') continue
                if (args.currency && t.currency !== args.currency) continue
                totals.set(
                    t.categoryId,
                    (totals.get(t.categoryId) ?? 0n) + t.amount,
                )
            }
            const cats = await ctx.db
                .query('categories')
                .withIndex('by_user_archived', (q) =>
                    q.eq('userId', userId).eq('isArchived', false),
                )
                .collect()
            const nameById = new Map(cats.map((c) => [c.id, c.name]))
            return {
                groupBy: 'category' as const,
                truncated,
                rows: [...totals.entries()].map(([categoryId, total]) => ({
                    categoryId,
                    name: nameById.get(categoryId) ?? '(unknown)',
                    totalCents: total,
                })),
            }
        }

        const accounts = await ctx.db
            .query('accounts')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .collect()
        const flows = new Map<
            string,
            { name: string; currency: string; in: bigint; out: bigint }
        >()
        for (const a of accounts) {
            flows.set(a.id, {
                name: a.name,
                currency: a.currency,
                in: 0n,
                out: 0n,
            })
        }
        for await (const t of stream) {
            scanned++
            if (scanned > MAX_SCAN) {
                truncated = true
                break
            }
            if (t.isArchived) continue
            const row = flows.get(t.accountId)
            if (row) {
                if (t.type === 'expense') row.out += t.amount
                else if (t.type === 'income') row.in += t.amount
                else if (t.type === 'transfer') row.out += t.amount
                else if (t.type === 'balance_adjustment') {
                    if (t.amount >= 0n) row.in += t.amount
                    else row.out += -t.amount
                }
            }
            if (t.type === 'transfer' && t.toAccountId) {
                const dest = flows.get(t.toAccountId)
                if (dest) dest.in += t.toAmount ?? t.amount
            }
        }
        return {
            groupBy: 'account' as const,
            truncated,
            rows: [...flows.entries()].map(([accountId, row]) => ({
                accountId,
                name: row.name,
                currency: row.currency,
                inCents: row.in,
                outCents: row.out,
                netCents: row.in - row.out,
            })),
        }
    },
})

// O(log n) balance read backed by two TableAggregates over `transactions`.
// See aggregates.ts for the namespace/sumValue contracts.
//
// Both aggregates are sorted by `date`, so excluding the movements that have
// not happened yet is an upper bound on the sum — still O(log n), with no rows
// read. A balance is always "as of" a moment; `asOfMs` says which one.
export async function computeAccountBalance(
    ctx: QueryCtx,
    userId: string,
    accountId: string,
    asOfMs: bigint,
): Promise<bigint> {
    const namespace = accountNamespace(userId, accountId)
    const bounds = { upper: { key: asOfMs, inclusive: false } } as const
    const [outflows, inflows] = await Promise.all([
        outflowsByAccount.sum(ctx, { namespace, bounds }),
        inflowsByAccount.sum(ctx, { namespace, bounds }),
    ])
    return BigInt(Math.round(outflows + inflows))
}

export const balance = query({
    args: { accountId: v.string(), asOfMs: v.int64() },
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
            args.asOfMs,
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
