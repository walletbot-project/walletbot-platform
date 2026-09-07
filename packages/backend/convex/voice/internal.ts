import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'

/**
 * Drops voice history past the twelve-month window the privacy policy sets.
 *
 * Sessions and their events age out on separate crons because the volumes are
 * nothing alike: a session is one row, its events are hundreds. Both walk a
 * retention-only index oldest-first in `limit`-sized batches, so neither ever
 * scans the table.
 *
 * The two are not transactionally paired, and they do not need to be. An event
 * always occurs after its session started, so a session is always collected
 * first, and the events left behind for one tick belong to a session no reader
 * can reach: `v1/voice/sessions.ts` finds events through the session, never on
 * their own.
 */
export const deleteOldVoiceSessions = internalMutation({
    args: { olderThanMs: v.number(), limit: v.number() },
    handler: async (ctx, args) => {
        const cutoff = BigInt(Date.now() - args.olderThanMs)
        const rows = await ctx.db
            .query('voiceSessions')
            .withIndex('by_startedAt', (q) => q.lt('startedAt', cutoff))
            .order('asc')
            .take(args.limit)

        for (const row of rows) {
            await ctx.db.delete(row._id)
        }
        return { deleted: rows.length }
    },
})

export const deleteOldVoiceSessionEvents = internalMutation({
    args: { olderThanMs: v.number(), limit: v.number() },
    handler: async (ctx, args) => {
        const cutoff = BigInt(Date.now() - args.olderThanMs)
        const rows = await ctx.db
            .query('voiceSessionEvents')
            .withIndex('by_occurredAt', (q) => q.lt('occurredAt', cutoff))
            .order('asc')
            .take(args.limit)

        for (const row of rows) {
            await ctx.db.delete(row._id)
        }
        return { deleted: rows.length }
    },
})
