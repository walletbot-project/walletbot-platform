import { occurrenceCount, recurrenceHorizon } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internal } from '../../_generated/api'
import type { Doc } from '../../_generated/dataModel'
import { mutation } from '../../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../../aggregates'
import { workflow } from '../../recurrences/workflow'
import { nextSeq } from '../../sync/helpers'
import { recordMovementCreated } from '../../telemetry/metrics'
import { requireAuth } from '../../users/helpers'

const recurrenceFrequency = v.union(
    v.literal('daily'),
    v.literal('weekly'),
    v.literal('monthly'),
    v.literal('yearly'),
    v.literal('customDays'),
)

/**
 * Creates a recurring rule together with its first occurrence, then hands the
 * rest to the workflow.
 *
 * The two are written in one mutation on purpose: a rule with no anchor
 * occurrence has no shape (the occurrences copy their fields from it), and the
 * batch materialiser refuses to run without one. Writing them separately would
 * leave a window where the series is uninterpretable.
 *
 * Occurrence 0 *is* the movement the user filled in, so it is an ordinary
 * transaction in every respect — that is the whole point of §2.5.
 */
export const create = mutation({
    args: {
        recurrenceId: v.string(),
        frequency: recurrenceFrequency,
        dayInterval: v.optional(v.int64()),
        endDate: v.optional(v.int64()),

        // The first occurrence, i.e. the movement the form was filled in with.
        transactionId: v.string(),
        type: v.union(v.literal('expense'), v.literal('income')),
        name: v.string(),
        description: v.optional(v.string()),
        amount: v.int64(),
        accountId: v.string(),
        categoryId: v.string(),
        date: v.int64(),
        dateConfirmed: v.boolean(),
        timeStatus: v.optional(
            v.union(
                v.literal('confirmed'),
                v.literal('approximation'),
                v.literal('none'),
            ),
        ),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        if (args.amount <= 0n) throw new Error('Amount must be positive')

        const account = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.accountId),
            )
            .unique()
        if (!account) throw new Error('Account not found')
        const category = await ctx.db
            .query('categories')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.categoryId),
            )
            .unique()
        if (!category) throw new Error('Category not found')

        const existing = await ctx.db
            .query('transactions')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.transactionId),
            )
            .unique()
        if (existing) throw new Error('Transaction id already exists')

        const now = BigInt(Date.now())

        await ctx.db.insert('recurrences', {
            userId,
            id: args.recurrenceId,
            frequency: args.frequency,
            dayInterval: args.dayInterval,
            anchorDate: args.date,
            endDate: args.endDate,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq: await nextSeq(ctx, userId),
        })

        const doc: Omit<Doc<'transactions'>, '_id' | '_creationTime'> = {
            userId,
            id: args.transactionId,
            type: args.type,
            name: args.name,
            description: args.description,
            status: 'cleared',
            date: args.date,
            dateConfirmed: args.dateConfirmed,
            timeStatus: args.timeStatus ?? 'none',
            accountId: args.accountId,
            categoryId: args.categoryId,
            amount: args.amount,
            currency: account.currency,
            recurrenceId: args.recurrenceId,
            recurrenceIndex: 0n,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq: await nextSeq(ctx, userId),
        }
        const inserted = await ctx.db.insert('transactions', doc)
        const row = await ctx.db.get(inserted)
        if (row) {
            await outflowsByAccount.insert(ctx, row)
            await inflowsByAccount.insert(ctx, row)
        }
        await recordMovementCreated(ctx, {
            userId,
            movementType: args.type,
            createdBy: 'form',
            ingestPath: 'direct_mutation',
        })

        // The range is resolved here, not inside the materialiser, so retries
        // fill the same window instead of re-reading a growing series.
        const total = occurrenceCount(
            Number(args.date),
            args.frequency,
            args.endDate === undefined ? null : Number(args.endDate),
            args.dayInterval === undefined ? 1 : Number(args.dayInterval),
        )
        await workflow.start(
            ctx,
            internal.recurrences.workflow.materializeRecurrence,
            {
                userId,
                recurrenceId: args.recurrenceId,
                from: 1, // Occurrence 0 is the transaction inserted above.
                to: total,
            },
        )

        return args.transactionId
    },
})

/**
 * Tops a rule up by another batch: the same N the rule was created with
 * (`recurrenceHorizon`), continuing from the **last occurrence that exists**.
 *
 * Not from the occurrence the user was looking at when they asked. Opening
 * September's movement of a series already materialised through November and
 * asking for 48 more has to mean December onwards — anything else would either
 * collide with the movements already there or leave a hole.
 *
 * Only for open-ended rules. A rule with an end date is already complete; more
 * occurrences would run past a boundary the user set on purpose, and moving
 * that boundary is editing the rule, not extending it.
 */
export const addOccurrences = mutation({
    args: { recurrenceId: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)

        const rule = await ctx.db
            .query('recurrences')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.recurrenceId),
            )
            .unique()
        if (!rule || rule.isArchived) throw new Error('Recurrence not found')
        if (rule.endDate !== undefined) {
            throw new Error('Recurrence has an end date')
        }

        // The highest occurrence index, not the newest date: once a single
        // occurrence's date can be edited, the two stop agreeing, and it is
        // the index that says which slots are taken.
        const last = await ctx.db
            .query('transactions')
            .withIndex('by_user_recurrence_index', (q) =>
                q.eq('userId', userId).eq('recurrenceId', args.recurrenceId),
            )
            .order('desc')
            .first()
        if (!last || last.recurrenceIndex === undefined) {
            throw new Error('Recurrence has no occurrences')
        }

        const count = recurrenceHorizon(
            rule.frequency,
            rule.dayInterval === undefined ? 1 : Number(rule.dayInterval),
        ).count
        const from = Number(last.recurrenceIndex) + 1

        await workflow.start(
            ctx,
            internal.recurrences.workflow.materializeRecurrence,
            { userId, recurrenceId: args.recurrenceId, from, to: from + count },
        )

        return count
    },
})
