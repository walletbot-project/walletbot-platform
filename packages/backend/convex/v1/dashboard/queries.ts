import { v } from 'convex/values'
import type { QueryCtx } from '../../_generated/server'
import { query } from '../../_generated/server'
import { resolveOccurrenceCutoff } from '../../occurrences/helpers'
import { requireAuth } from '../../users/helpers'
import { computeAccountBalance } from '../transactions/queries'
import {
    absCents,
    evaluateConfig,
    MAX_DASHBOARD_ROWS,
    netCents,
} from './helpers'

/** Rows the transaction-list widget may request. */
const MAX_LIST_LIMIT = 50

/** Buckets a breakdown chart renders before the tail is folded away. */
const MAX_SLICES = 12

export const layout = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        const [widgets, filters] = await Promise.all([
            ctx.db
                .query('dashboardWidgets')
                .withIndex('by_user_archived', (q) =>
                    q.eq('userId', userId).eq('isArchived', false),
                )
                .take(MAX_DASHBOARD_ROWS),
            ctx.db
                .query('savedFilters')
                .withIndex('by_user_archived', (q) =>
                    q.eq('userId', userId).eq('isArchived', false),
                )
                .take(MAX_DASHBOARD_ROWS),
        ])

        return {
            widgets: widgets
                .slice()
                .sort((a, b) => a.position - b.position)
                .map((w) => ({
                    id: w.id,
                    type: w.type,
                    filterId: w.filterId ?? null,
                    position: w.position,
                    width: w.width,
                    options: w.options,
                })),
            filters: filters.map((f) => ({
                id: f.id,
                name: f.name,
                config: f.config,
            })),
        }
    },
})

export const stat = query({
    args: {
        config: v.string(),
        asOfMs: v.optional(v.int64()),
        aggregation: v.union(
            v.literal('sum'),
            v.literal('net'),
            v.literal('count'),
        ),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const asOfMs = resolveOccurrenceCutoff(args.asOfMs)
        const { rows, truncated } = await evaluateConfig(
            ctx,
            userId,
            args.config,
            null,
            asOfMs,
        )

        let amount = 0n
        for (const txn of rows) {
            amount += args.aggregation === 'net' ? netCents(txn) : absCents(txn)
        }
        return {
            aggregation: args.aggregation,
            amountCents: args.aggregation === 'count' ? 0n : amount,
            count: rows.length,
            truncated,
        }
    },
})

export const transactions = query({
    args: {
        config: v.string(),
        limit: v.optional(v.number()),
        asOfMs: v.optional(v.int64()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const asOfMs = resolveOccurrenceCutoff(args.asOfMs)
        const limit = Math.min(
            Math.max(Math.trunc(args.limit ?? 5), 1),
            MAX_LIST_LIMIT,
        )
        const { rows } = await evaluateConfig(
            ctx,
            userId,
            args.config,
            limit,
            asOfMs,
        )
        return rows
    },
})

/**
 * Balance "as of now" (never date-bounded) — the balance-card contract from the
 * design doc.
 *
 * Scope: every non-archived account in `currency`, narrowed to `accountIds`
 * when that list is non-empty. An empty or omitted list is the whole currency,
 * which is what every card written before account scoping stores, so those keep
 * their meaning. Ids are still intersected with the currency, so a stale id —
 * an account since archived, deleted, or switched to another currency — drops
 * out of the sum instead of being counted or throwing.
 */
export const currencyBalance = query({
    args: {
        currency: v.string(),
        accountIds: v.optional(v.array(v.string())),
        asOfMs: v.optional(v.int64()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const asOfMs = resolveOccurrenceCutoff(args.asOfMs)
        const accounts = await ctx.db
            .query('accounts')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .take(MAX_DASHBOARD_ROWS)
        const scope = args.accountIds ?? []
        const matching = accounts.filter(
            (account) =>
                account.currency === args.currency &&
                (scope.length === 0 || scope.includes(account.id)),
        )
        if (matching.length === 0) {
            return { balance: 0n, accountCount: 0 }
        }

        const balances = await Promise.all(
            matching.map((account) =>
                computeAccountBalance(ctx, userId, account.id, asOfMs),
            ),
        )
        return {
            balance: balances.reduce((total, value) => total + value, 0n),
            accountCount: matching.length,
        }
    },
})

export const breakdown = query({
    args: {
        config: v.string(),
        asOfMs: v.optional(v.int64()),
        groupBy: v.union(
            v.literal('category'),
            v.literal('account'),
            v.literal('month'),
        ),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const asOfMs = resolveOccurrenceCutoff(args.asOfMs)
        const { rows, truncated } = await evaluateConfig(
            ctx,
            userId,
            args.config,
            null,
            asOfMs,
        )

        // Transfers move money between the user's own accounts; counting them
        // in a "where did it go" breakdown double-reports it.
        const relevant = rows.filter((txn) => txn.type !== 'transfer')
        const totals = new Map<string, bigint>()
        for (const txn of relevant) {
            const key =
                args.groupBy === 'category'
                    ? (txn.categoryId ?? '')
                    : args.groupBy === 'account'
                      ? txn.accountId
                      : monthKey(txn.date)
            totals.set(key, (totals.get(key) ?? 0n) + absCents(txn))
        }

        const labels = await resolveLabels(ctx, userId, args.groupBy, [
            ...totals.keys(),
        ])

        const slices = [...totals.entries()]
            .map(([key, totalCents]) => ({
                key,
                label: labels.get(key)?.label ?? key,
                colorHex: labels.get(key)?.color ?? null,
                totalCents,
            }))
            .sort((a, b) =>
                args.groupBy === 'month'
                    ? a.key.localeCompare(b.key)
                    : Number(b.totalCents - a.totalCents),
            )

        return {
            slices: slices.slice(0, MAX_SLICES),
            // Partial either way: the scan was capped, or the tail was folded.
            truncated: truncated || slices.length > MAX_SLICES,
        }
    },
})

function monthKey(dateMs: bigint): string {
    const date = new Date(Number(dateMs))
    return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`
}

async function resolveLabels(
    ctx: QueryCtx,
    userId: string,
    groupBy: 'category' | 'account' | 'month',
    keys: string[],
): Promise<Map<string, { label: string; color: string | null }>> {
    const out = new Map<string, { label: string; color: string | null }>()
    if (groupBy === 'month') {
        for (const key of keys) out.set(key, { label: key, color: null })
        return out
    }
    const table = groupBy === 'category' ? 'categories' : 'accounts'
    for (const key of keys) {
        if (!key) continue
        const row = await ctx.db
            .query(table)
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', key),
            )
            .unique()
        if (row) out.set(key, { label: row.name, color: row.color ?? null })
    }
    return out
}
