import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// Voice/chat history is intentionally isolated from the financial sync tables:
// it is append-only, high volume, and has independent retention semantics.
export const voiceSessions = defineTable({
    userId: v.string(),
    sessionId: v.string(),
    model: v.string(),
    status: v.string(),
    startedAt: v.int64(),
    updatedAt: v.int64(),
    endedAt: v.optional(v.int64()),
    endedExplicitly: v.boolean(),
})
    .index('by_userId_and_sessionId', ['userId', 'sessionId'])
    // Retention only. Walked oldest-first by the twelve-month cron, never by a
    // client read.
    .index('by_startedAt', ['startedAt'])

export const voiceSessionEvents = defineTable({
    userId: v.string(),
    sessionId: v.string(),
    eventId: v.string(),
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
    .index('by_userId_and_sessionId_and_sequence', [
        'userId',
        'sessionId',
        'sequence',
    ])
    .index('by_userId_and_eventId', ['userId', 'eventId'])
    // Retention only, same as `voiceSessions.by_startedAt`.
    .index('by_occurredAt', ['occurredAt'])
