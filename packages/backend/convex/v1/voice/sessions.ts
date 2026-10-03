import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import { insertMetricBatch } from '../../telemetry/metrics'
import type { MetricInput } from '../../telemetry/types'
import { requireAuth } from '../../users/helpers'
import { webVoiceMetric } from './metrics'
import { sessionFieldsChanged } from './utils'

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

/// V1 append-only voice history replication contract. Audio bytes remain on
/// device; their size/type travel with the semantic and protocol event log.
export const appendEvents = mutation({
    args: {
        ownerId: v.string(),
        source: v.optional(v.literal('web')),
        session: sessionArg,
        events: v.array(eventArg),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        if (args.ownerId !== userId) {
            throw new Error(
                'Voice session owner does not match authenticated user',
            )
        }
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
            if (sessionFieldsChanged(existingSession, sessionFields)) {
                await ctx.db.patch(existingSession._id, sessionFields)
            }
        } else {
            await ctx.db.insert('voiceSessions', sessionFields)
        }

        let inserted = 0
        const metrics: MetricInput[] = []
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
            if (args.source === 'web') {
                const metric = webVoiceMetric({
                    userId,
                    sessionId: args.session.id,
                    event,
                })
                if (metric) metrics.push(metric)
            }
        }
        // The event-id dedupe above and metric insertion share this transaction.
        // Retrying a history upload cannot count the same usage twice.
        if (metrics.length)
            await insertMetricBatch(ctx, { metrics, receivedAt: Date.now() })
        return { ok: true, inserted }
    },
})
