import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// WhatsApp conversation state — one row per (waId, phoneNumberId).
//
// `status` + `runId` are the agent's lock, and the reason this feature needs no
// external lock service. Convex mutations are serializable transactions, so
// "is a turn already running?" and "start a turn" happen atomically: two
// webhooks landing at the same instant can never both start a worker for the
// same conversation. See docs/whatsapp-platform.md and whatsapp/internal.ts.
//
// `runId` is a fence. If a turn's action dies and the reaper releases the lock,
// a zombie that resumes later carries a stale runId and every mutation it
// attempts is rejected, so it cannot corrupt state a newer turn now owns.
export const whatsappConversations = defineTable({
    waId: v.string(),
    phoneNumberId: v.string(),
    // Set once this number is linked to a Wallet Bot account. Until then the
    // agent has no accounts to act on.
    userId: v.optional(v.string()),
    status: v.union(v.literal('idle'), v.literal('processing')),
    runId: v.optional(v.string()),
    processingStartedAt: v.optional(v.number()),
    lastInboundAt: v.number(),
    // lastInboundAt + 24h. The service window is tracked on our side because
    // Meta accepts out-of-window sends with `200` + a wamid and then silently
    // discards them — verified 2026-08-16. The API response cannot be trusted
    // to tell us a send was undeliverable.
    windowExpiresAt: v.number(),
    createdAt: v.number(),
})
    .index('by_waId_and_phoneNumberId', ['waId', 'phoneNumberId'])
    // Reaper scan: find turns that have held the lock too long.
    .index('by_status_and_processingStartedAt', [
        'status',
        'processingStartedAt',
    ])

// The inbound queue. Rows are claimed in batches by a turn, never one at a
// time — a user who sends three fragments gets one reply, not three.
export const whatsappInboundMessages = defineTable({
    conversationId: v.id('whatsappConversations'),
    // Meta's message id, and our dedupe key: webhook deliveries are retried,
    // so the same wamid arrives more than once and must not queue twice.
    wamid: v.string(),
    waId: v.string(),
    type: v.string(),
    text: v.optional(v.string()),
    // Media is referenced by id and must be downloaded from the Graph API
    // separately; we do not inline it here.
    mediaId: v.optional(v.string()),
    // Meta's own timestamp, converted to ms.
    sentAt: v.number(),
    receivedAt: v.number(),
    status: v.union(
        v.literal('pending'),
        v.literal('claimed'),
        v.literal('processed'),
        v.literal('failed'),
    ),
    claimedByRunId: v.optional(v.string()),
    failureReason: v.optional(v.string()),
})
    .index('by_wamid', ['wamid'])
    .index('by_conversationId_and_status', ['conversationId', 'status'])

// Outbound log. This exists because a send response proves nothing: the only
// evidence a message was delivered is a status webhook updating this row.
export const whatsappOutboundMessages = defineTable({
    conversationId: v.id('whatsappConversations'),
    // Absent when the send call itself failed, so there is no wamid to track.
    wamid: v.optional(v.string()),
    text: v.string(),
    status: v.union(
        v.literal('queued'),
        v.literal('sent'),
        v.literal('delivered'),
        v.literal('read'),
        v.literal('failed'),
    ),
    errorCode: v.optional(v.number()),
    errorMessage: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
})
    .index('by_wamid', ['wamid'])
    .index('by_conversationId', ['conversationId'])
