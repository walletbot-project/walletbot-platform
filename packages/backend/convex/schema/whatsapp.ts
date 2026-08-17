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
    // agent has no accounts to act on — and, more importantly, an unlinked
    // conversation never reaches the model or any tool. The webhook is public
    // and unauthenticated (R-020), so this field is the authorization boundary
    // for the whole feature, not a convenience.
    userId: v.optional(v.string()),
    linkedAt: v.optional(v.number()),
    // Guessing a link code is an online attack against a public endpoint, so
    // attempts are counted per conversation and backed off. Reset on success.
    failedLinkAttempts: v.optional(v.number()),
    linkBlockedUntil: v.optional(v.number()),
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
    // "Which numbers are linked to my account?" and unlink-all.
    .index('by_userId', ['userId'])

// Short-lived codes that link a wa_id to a Wallet Bot account.
//
// Linking must start from an authenticated session — never from WhatsApp —
// because anyone can message the business number. The code is the proof that
// whoever is holding the phone also controls a logged-in Wallet Bot account.
//
// The code is stored in plain text on purpose. Hashing would look safer but
// buys nothing here: the alphabet is 32 characters and the code is 8 long, so
// an attacker who could read this table could also exhaust the SHA-256
// preimage space in well under the code's 10-minute lifetime. The real
// controls are the short expiry, single use, and the per-conversation attempt
// limit — not obscuring a value that is about to be useless anyway.
export const whatsappLinkCodes = defineTable({
    code: v.string(),
    userId: v.string(),
    createdAt: v.number(),
    expiresAt: v.number(),
    // Kept after consumption instead of deleting the row, so a user who sends
    // the same code twice gets "already used" rather than a wrong-code
    // penalty. The purge cron removes them once they are safely stale.
    consumedAt: v.optional(v.number()),
    consumedByWaId: v.optional(v.string()),
})
    .index('by_code', ['code'])
    .index('by_userId', ['userId'])
    .index('by_expiresAt', ['expiresAt'])

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
