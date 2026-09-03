import { occurrenceCount, recurrenceHorizon } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internal } from '../../_generated/api'
import type { Doc } from '../../_generated/dataModel'
import type { MutationCtx } from '../../_generated/server'
import { mutation } from '../../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../../aggregates'
import { applyOccurrencePatch } from '../../recurrences/internal'
import { workflow } from '../../recurrences/workflow'
import { nextSeq, writeTombstone } from '../../sync/helpers'
import { recordMovementCreated } from '../../telemetry/metrics'
import {
    aggregateInsert,
    archiveTransactionRow,
    occurrencePatch,
} from '../../transactions/helpers'
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

// ───── "This one and the ones after it" ─────

/**
 * The occurrence a scoped edit or delete starts from, with its rule.
 *
 * Both operations are addressed by transaction id — that is what the user
 * tapped — and resolved to a (rule, index) pair here, because everything past
 * this point works on the series.
 */
async function resolveOccurrence(
    ctx: MutationCtx,
    userId: string,
    transactionId: string,
) {
    const row = await ctx.db
        .query('transactions')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', transactionId),
        )
        .unique()
    if (!row) throw new Error('Transaction not found')
    const recurrenceId = row.recurrenceId
    if (recurrenceId === undefined || row.recurrenceIndex === undefined) {
        return { row, rule: null, index: 0 }
    }
    const rule = await ctx.db
        .query('recurrences')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', recurrenceId),
        )
        .unique()
    // A null rule reads as "no series": the caller then treats "this and the
    // ones after it" as this one, which is what it means when there are none.
    return { row, rule, index: Number(row.recurrenceIndex) }
}

/**
 * Truncates a rule so it stops claiming the occurrences from `index` on.
 *
 * The rule's end date is what `X/N` and the top-up button read, so leaving it
 * pointing past a tail that no longer exists would have the detail describe a
 * series longer than the one on screen. Cutting at the *previous* occurrence's
 * date keeps the boundary inclusive-of-what-remains; at index 0 there is no
 * previous occurrence, so the rule itself goes.
 */
async function truncateRuleBefore(
    ctx: MutationCtx,
    userId: string,
    rule: Doc<'recurrences'>,
    index: number,
): Promise<void> {
    const now = BigInt(Date.now())
    if (index === 0) {
        await ctx.db.patch(rule._id, {
            isArchived: true,
            updatedAt: now,
            seq: await nextSeq(ctx, userId),
        })
        await writeTombstone(ctx, {
            userId,
            tableName: 'recurrences',
            entityId: rule.id,
            seq: await nextSeq(ctx, userId),
        })
        return
    }
    const previous = await ctx.db
        .query('transactions')
        .withIndex('by_user_recurrence_index', (q) =>
            q
                .eq('userId', userId)
                .eq('recurrenceId', rule.id)
                .eq('recurrenceIndex', BigInt(index - 1)),
        )
        .first()
    if (!previous) return
    await ctx.db.patch(rule._id, {
        endDate: previous.date,
        updatedAt: now,
        seq: await nextSeq(ctx, userId),
    })
}

/**
 * Carries an edit to this occurrence and every later one.
 *
 * Only the value fields. A change of cadence or of the anchor date is a
 * `splitSeries`, not this: the occurrences before this one keep their own
 * spacing, so "from here on, weekly" describes two rules, not one.
 */
export const updateFuture = mutation({
    args: {
        transactionId: v.string(),
        patch: occurrencePatch,
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        if (args.patch.amount !== undefined && args.patch.amount <= 0n) {
            throw new Error('Amount must be positive')
        }
        const { row, rule, index } = await resolveOccurrence(
            ctx,
            userId,
            args.transactionId,
        )

        // This one synchronously, so the screen the user is looking at is
        // right the moment the mutation returns; the tail follows in batches.
        await applyOccurrencePatch(ctx, userId, row, args.patch)
        if (!rule) return
        await workflow.start(
            ctx,
            internal.recurrences.workflow.updateFutureOccurrences,
            {
                userId,
                recurrenceId: rule.id,
                fromIndex: index + 1,
                patch: args.patch,
            },
        )
    },
})

/** Deletes this occurrence and every later one, and truncates the rule. */
export const deleteFuture = mutation({
    args: { transactionId: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const { row, rule, index } = await resolveOccurrence(
            ctx,
            userId,
            args.transactionId,
        )

        if (!rule) {
            await archiveTransactionRow(ctx, userId, row)
            return
        }
        // Truncate first, while occurrence `index - 1` is still the last one
        // standing — after the tail goes, its date is what the rule ends on.
        await truncateRuleBefore(ctx, userId, rule, index)
        await archiveTransactionRow(ctx, userId, row)
        await workflow.start(
            ctx,
            internal.recurrences.workflow.archiveFutureOccurrences,
            { userId, recurrenceId: rule.id, fromIndex: index + 1 },
        )
    },
})

/**
 * Re-cadences a series from this occurrence on, by splitting it in two.
 *
 * There is no way to express "from here on, weekly" as one rule: every
 * occurrence is projected from the anchor by index
 * (docs/recurrency-design.md §2.3), so changing the cadence would move the
 * occurrences *before* this one too. What the user means is two rules — the
 * original one ending where they stopped it, and a new one starting here — and
 * that is what this writes.
 *
 * Built out of the two operations that already exist: the old tail is deleted
 * and a new series is created at this date. The new rule inherits the old
 * one's end date, because the user only moved the cadence, not the end.
 */
export const splitSeries = mutation({
    args: {
        transactionId: v.string(),
        recurrenceId: v.string(), // the new rule's client-generated id
        frequency: recurrenceFrequency,
        dayInterval: v.optional(v.int64()),
        date: v.int64(),
        dateConfirmed: v.boolean(),
        timeStatus: v.optional(
            v.union(
                v.literal('confirmed'),
                v.literal('approximation'),
                v.literal('none'),
            ),
        ),
        patch: occurrencePatch,
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const {
            row,
            rule: oldRule,
            index,
        } = await resolveOccurrence(ctx, userId, args.transactionId)
        if (!oldRule) {
            throw new Error('Transaction is not part of a recurring series')
        }

        await truncateRuleBefore(ctx, userId, oldRule, index)

        // The old tail, this occurrence included: it is being replaced by the
        // new series, whose occurrence 0 sits at the edited date.
        await archiveTransactionRow(ctx, userId, row)
        await workflow.start(
            ctx,
            internal.recurrences.workflow.archiveFutureOccurrences,
            { userId, recurrenceId: oldRule.id, fromIndex: index + 1 },
        )

        const now = BigInt(Date.now())
        await ctx.db.insert('recurrences', {
            userId,
            id: args.recurrenceId,
            frequency: args.frequency,
            dayInterval: args.dayInterval,
            anchorDate: args.date,
            endDate: oldRule.endDate,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq: await nextSeq(ctx, userId),
        })

        const account = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q
                    .eq('userId', userId)
                    .eq('id', args.patch.accountId ?? row.accountId),
            )
            .unique()
        if (!account) throw new Error('Account not found')

        const anchorId = crypto.randomUUID()
        const doc: Omit<Doc<'transactions'>, '_id' | '_creationTime'> = {
            userId,
            id: anchorId,
            type: row.type,
            name: args.patch.name ?? row.name,
            description: args.patch.description ?? row.description,
            status: row.status,
            date: args.date,
            dateConfirmed: args.dateConfirmed,
            timeStatus: args.timeStatus ?? row.timeStatus,
            accountId: account.id,
            categoryId: args.patch.categoryId ?? row.categoryId,
            amount: args.patch.amount ?? row.amount,
            currency: account.currency,
            recurrenceId: args.recurrenceId,
            recurrenceIndex: 0n,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq: await nextSeq(ctx, userId),
        }
        const inserted = await ctx.db.insert('transactions', doc)
        await aggregateInsert(ctx, inserted)

        const total = occurrenceCount(
            Number(args.date),
            args.frequency,
            oldRule.endDate === undefined ? null : Number(oldRule.endDate),
            args.dayInterval === undefined ? 1 : Number(args.dayInterval),
        )
        await workflow.start(
            ctx,
            internal.recurrences.workflow.materializeRecurrence,
            {
                userId,
                recurrenceId: args.recurrenceId,
                from: 1,
                to: total,
            },
        )

        return anchorId
    },
})
