import { pastCutoffBigInt } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internal } from '../_generated/api'
import { internalMutation } from '../_generated/server'
import { migrations } from '../migrations'
import { nextSeq } from '../sync/helpers'
import { republishTransactionTags } from './helpers'

export const republishTags = internalMutation({
    args: { userId: v.string(), id: v.string(), cursor: v.string() },
    handler: async (ctx, args) => {
        await republishTransactionTags(ctx, args, args.cursor)
    },
})

// The cron also invalidates old web subscriptions that omit the cutoff. The
// migration is resumable and becomes a no-op once its existing rows are queued.
export const tick = internalMutation({
    args: {},
    handler: async (ctx) => {
        const cutoff = pastCutoffBigInt()
        const clock = await ctx.db
            .query('occurrenceClock')
            .withIndex('by_key', (q) => q.eq('key', 'singleton'))
            .unique()
        if (!clock)
            await ctx.db.insert('occurrenceClock', { key: 'singleton', cutoff })
        else if (clock.cutoff !== cutoff)
            await ctx.db.patch(clock._id, { cutoff })
        await migrations.runOne(
            ctx,
            internal.migrations.backfillLegacyOccurrences,
        )
        await ctx.scheduler.runAfter(
            0,
            internal.occurrences.internal.publishDue,
            {},
        )
    },
})

export const publishDue = internalMutation({
    args: {},
    handler: async (ctx) => {
        const rows = await ctx.db
            .query('transactions')
            .withIndex('by_legacyPendingDate', (q) =>
                q
                    .gt('legacyPendingDate', 0n)
                    .lt('legacyPendingDate', pastCutoffBigInt()),
            )
            .take(50)
        for (const row of rows) {
            // Visibility is not a business edit: retain updatedAt so an
            // offline user's newer edit still wins the usual LWW merge.
            await ctx.db.patch(row._id, {
                legacyPendingDate: undefined,
                seq: await nextSeq(ctx, row.userId),
            })
            await republishTransactionTags(ctx, row)
        }
        if (rows.length === 50) {
            await ctx.scheduler.runAfter(
                0,
                internal.occurrences.internal.publishDue,
                {},
            )
        }
    },
})

// Legacy push advances past its own write. A later seq makes it pull the
// projection too when that write moved/created a transaction in the future.
export const refreshLegacyWrites = internalMutation({
    args: { userId: v.string(), ids: v.array(v.string()) },
    handler: async (ctx, args) => {
        for (const id of args.ids) {
            const row = await ctx.db
                .query('transactions')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', args.userId).eq('id', id),
                )
                .unique()
            if (!row || row.isArchived || row.date < pastCutoffBigInt())
                continue
            await ctx.db.patch(row._id, {
                seq: await nextSeq(ctx, args.userId),
            })
        }
    },
})
