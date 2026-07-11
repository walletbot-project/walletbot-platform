import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { requireAuth } from '../users/helpers'

const sessionArg = v.object({
    id: v.string(),
    model: v.string(),
    status: v.string(),
    startedAt: v.int64(),
    updatedAt: v.int64(),
    endedAt: v.optional(v.int64()),
    endedExplicitly: v.boolean(),
})

const eventArg = v.object({
    id: v.string(),
    sequence: v.number(),
    occurredAt: v.int64(),
    type: v.string(),
    direction: v.string(),
    modality: v.optional(v.string()),
    payloadJson: v.string(),
    rawJson: v.optional(v.string()),
    binaryByteLength: v.optional(v.number()),
    binaryMimeType: v.optional(v.string()),
})

/// Idempotent append endpoint used by the native outbox. Audio bytes remain on
/// device; their size/type travel with the complete semantic/protocol log.
export const appendEvents = mutation({
    args: {
        session: sessionArg,
        events: v.array(eventArg),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const existingSession = await ctx.db
            .query('voiceSessions')
            .withIndex('by_userId_and_sessionId', (q) =>
                q.eq('userId', userId).eq('sessionId', args.session.id),
            )
            .unique()

        const sessionFields = {
            userId,
            sessionId: args.session.id,
            model: args.session.model,
            status: args.session.status,
            startedAt: args.session.startedAt,
            updatedAt: args.session.updatedAt,
            endedAt: args.session.endedAt,
            endedExplicitly: args.session.endedExplicitly,
        }
        if (existingSession) {
            await ctx.db.patch(existingSession._id, sessionFields)
        } else {
            await ctx.db.insert('voiceSessions', sessionFields)
        }

        let inserted = 0
        for (const event of args.events) {
            const existing = await ctx.db
                .query('voiceSessionEvents')
                .withIndex('by_userId_and_eventId', (q) =>
                    q.eq('userId', userId).eq('eventId', event.id),
                )
                .unique()
            if (existing) continue
            await ctx.db.insert('voiceSessionEvents', {
                userId,
                sessionId: args.session.id,
                eventId: event.id,
                sequence: event.sequence,
                occurredAt: event.occurredAt,
                type: event.type,
                direction: event.direction,
                modality: event.modality,
                payloadJson: event.payloadJson,
                rawJson: event.rawJson,
                binaryByteLength: event.binaryByteLength,
                binaryMimeType: event.binaryMimeType,
            })
            inserted += 1
        }
        return { ok: true, inserted }
    },
})
