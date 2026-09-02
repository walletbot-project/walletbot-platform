import { occurrenceCount, occurrenceDateMs } from '@wallet-bot/shared'
import { v } from 'convex/values'
import type { Doc } from '../_generated/dataModel'
import { internalMutation, internalQuery } from '../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../aggregates'
import { nextSeq } from '../sync/helpers'

/**
 * How many occurrences one mutation materialises. A whole 500-occurrence rule
 * in a single transaction would be 500 inserts plus 1000 aggregate updates —
 * well past what one mutation should attempt. The workflow walks the batches.
 */
export const BATCH_SIZE = 50

export const describeSeries = internalQuery({
    args: { userId: v.string(), recurrenceId: v.string() },
    handler: async (ctx, args) => {
        const rule = await ctx.db
            .query('recurrences')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', args.userId).eq('id', args.recurrenceId),
            )
            .unique()
        if (!rule) return null
        return {
            total: occurrenceCount(
                Number(rule.anchorDate),
                rule.frequency,
                rule.endDate === undefined ? null : Number(rule.endDate),
                rule.dayInterval === undefined ? 1 : Number(rule.dayInterval),
            ),
        }
    },
})

/**
 * Materialises occurrences `[from, from + BATCH_SIZE)` of a rule.
 *
 * Idempotent by construction: it reads which indices the series already has
 * and inserts only the gaps. A workflow step that is retried after a partial
 * failure therefore completes the batch instead of duplicating it — which
 * matters, because these are real transactions and a duplicate is money the
 * user never spent.
 */
export const materializeBatch = internalMutation({
    args: {
        userId: v.string(),
        recurrenceId: v.string(),
        from: v.number(),
    },
    handler: async (ctx, args): Promise<{ done: boolean; next: number }> => {
        const rule = await ctx.db
            .query('recurrences')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', args.userId).eq('id', args.recurrenceId),
            )
            .unique()
        // The rule was deleted while the workflow was running: stop rather
        // than resurrect occurrences for something that no longer exists.
        if (!rule || rule.isArchived) return { done: true, next: args.from }

        const existing = await ctx.db
            .query('transactions')
            .withIndex('by_user_recurrence_date', (q) =>
                q
                    .eq('userId', args.userId)
                    .eq('recurrenceId', args.recurrenceId),
            )
            .collect()

        const anchor = existing.find((t) => t.recurrenceIndex === 0n)
        // Occurrence 0 *is* the transaction the user created; without it there
        // is nothing to copy and the series has no shape.
        if (!anchor) return { done: true, next: args.from }

        const present = new Set(
            existing.map((t) => Number(t.recurrenceIndex ?? -1)),
        )

        const total = occurrenceCount(
            Number(rule.anchorDate),
            rule.frequency,
            rule.endDate === undefined ? null : Number(rule.endDate),
            rule.dayInterval === undefined ? 1 : Number(rule.dayInterval),
        )
        const to = Math.min(args.from + BATCH_SIZE, total)

        const now = BigInt(Date.now())
        for (let index = args.from; index < to; index += 1) {
            if (present.has(index)) continue
            const date = occurrenceDateMs(
                Number(rule.anchorDate),
                rule.frequency,
                index,
                rule.dayInterval === undefined ? 1 : Number(rule.dayInterval),
            )
            const seq = await nextSeq(ctx, args.userId)
            const doc: Omit<Doc<'transactions'>, '_id' | '_creationTime'> = {
                userId: args.userId,
                id: crypto.randomUUID(),
                type: anchor.type,
                name: anchor.name,
                description: anchor.description,
                status: anchor.status,
                date: BigInt(date),
                dateConfirmed: anchor.dateConfirmed,
                timeStatus: anchor.timeStatus,
                accountId: anchor.accountId,
                categoryId: anchor.categoryId,
                amount: anchor.amount,
                currency: anchor.currency,
                toAccountId: anchor.toAccountId,
                toAmount: anchor.toAmount,
                toCurrency: anchor.toCurrency,
                exchangeRate: anchor.exchangeRate,
                recurrenceId: args.recurrenceId,
                recurrenceIndex: BigInt(index),
                isArchived: false,
                createdAt: now,
                updatedAt: now,
                seq,
            }
            const inserted = await ctx.db.insert('transactions', doc)
            const row = await ctx.db.get(inserted)
            if (row) {
                await outflowsByAccount.insert(ctx, row)
                await inflowsByAccount.insert(ctx, row)
            }
        }

        return { done: to >= total, next: to }
    },
})
