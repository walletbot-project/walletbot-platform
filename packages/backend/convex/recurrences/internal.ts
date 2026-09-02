import { occurrenceDateMs } from '@wallet-bot/shared'
import { v } from 'convex/values'
import type { Doc } from '../_generated/dataModel'
import { internalMutation } from '../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../aggregates'
import { nextSeq } from '../sync/helpers'

/**
 * How many occurrences one mutation materialises. A whole 500-occurrence rule
 * in a single transaction would be 500 inserts plus 1000 aggregate updates —
 * well past what one mutation should attempt. The workflow walks the batches.
 */
export const BATCH_SIZE = 50

/**
 * Materialises occurrences `[from, min(from + BATCH_SIZE, to))` of a rule.
 *
 * The range is an *argument*, never re-derived here. That is what makes a
 * top-up safe: "add 48 more" resolves to a concrete window at click time, so a
 * retried step fills that same window instead of reading a series that has
 * since grown and extending it again.
 *
 * Idempotent within the window: it reads which occurrences already exist and
 * inserts only the gaps. That matters because these are real transactions, and
 * a duplicate is money the user never spent.
 */
export const materializeBatch = internalMutation({
    args: {
        userId: v.string(),
        recurrenceId: v.string(),
        from: v.number(),
        to: v.number(),
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

        const anchorMs = Number(rule.anchorDate)
        const dayInterval =
            rule.dayInterval === undefined ? 1 : Number(rule.dayInterval)

        // Occurrence 0 *is* the transaction the user created; without it there
        // is nothing to copy and the series has no shape. It is also what the
        // new movements are copied *from*, rather than the last occurrence:
        // the anchor is the rule's shape, and letting one edited occurrence
        // redefine the future series is exactly the choice "this one" vs
        // "this one and the ones after it" exists to make explicit.
        const anchor = await ctx.db
            .query('transactions')
            .withIndex('by_user_recurrence_index', (q) =>
                q
                    .eq('userId', args.userId)
                    .eq('recurrenceId', args.recurrenceId)
                    .eq('recurrenceIndex', 0n),
            )
            .first()
        if (!anchor) return { done: true, next: args.from }

        const to = Math.min(args.from + BATCH_SIZE, args.to)
        if (args.from >= to) return { done: true, next: args.from }

        // Exactly the occurrences of `[from, to)` — bounded work per batch,
        // rather than re-reading the whole series (which grows with every
        // top-up). Addressed by index, not by date, so an occurrence whose
        // date was edited on its own still counts as present.
        const existing = await ctx.db
            .query('transactions')
            .withIndex('by_user_recurrence_index', (q) =>
                q
                    .eq('userId', args.userId)
                    .eq('recurrenceId', args.recurrenceId)
                    .gte('recurrenceIndex', BigInt(args.from))
                    .lt('recurrenceIndex', BigInt(to)),
            )
            .collect()
        const present = new Set(existing.map((t) => t.recurrenceIndex))

        const now = BigInt(Date.now())
        for (let index = args.from; index < to; index += 1) {
            if (present.has(BigInt(index))) continue
            const date = BigInt(
                occurrenceDateMs(anchorMs, rule.frequency, index, dayInterval),
            )
            const seq = await nextSeq(ctx, args.userId)
            const doc: Omit<Doc<'transactions'>, '_id' | '_creationTime'> = {
                userId: args.userId,
                id: crypto.randomUUID(),
                type: anchor.type,
                name: anchor.name,
                description: anchor.description,
                status: anchor.status,
                date,
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

        return { done: to >= args.to, next: to }
    },
})
