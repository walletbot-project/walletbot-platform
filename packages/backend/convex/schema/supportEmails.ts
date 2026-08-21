import { defineTable } from 'convex/server'
import { v } from 'convex/values'

/**
 * One row per inbound email Resend accepted for a support mailbox
 * (`support/utils.ts:SUPPORT_ADDRESSES`). Written only by the inbound webhook
 * pipeline (`support/http.ts` → `support/actions.ts` → `support/internal.ts`),
 * read only by the admin-gated `v1/support/queries`.
 *
 * Not a synced table: it never reaches a native or web client through
 * `v1/sync`, so it forces no sync-contract or drift schema bump.
 *
 * `resendEmailId` is the idempotency key. Resend retries a webhook until it
 * gets a 2xx, so the same inbound email can arrive more than once; the unique
 * lookup on `by_resendEmailId` is what keeps that from duplicating rows or
 * re-forwarding a message that was already delivered to the Gmail address.
 */
/**
 * Attachment metadata as stored on a row. Exported so the ingest mutation in
 * `support/internal.ts` validates its argument against the same shape the
 * table declares, instead of a second copy that could drift from it.
 */
export const supportEmailAttachment = v.object({
    id: v.string(),
    filename: v.union(v.string(), v.null()),
    // Null on the degraded path: the webhook's own attachment metadata carries
    // no size, only the `receiving.get` response does. See
    // `support/actions.ts` for when the row falls back to webhook metadata.
    size: v.union(v.number(), v.null()),
    contentType: v.string(),
    contentId: v.union(v.string(), v.null()),
    contentDisposition: v.union(v.string(), v.null()),
})

export const supportEmails = defineTable({
    resendEmailId: v.string(),
    from: v.string(),
    to: v.array(v.string()),
    cc: v.array(v.string()),
    bcc: v.array(v.string()),
    replyTo: v.array(v.string()),
    receivedFor: v.array(v.string()),
    subject: v.string(),
    messageId: v.string(),
    html: v.union(v.string(), v.null()),
    text: v.union(v.string(), v.null()),
    // True when either body hit the cap in `support/utils.ts`. A truncated
    // archive must never be mistaken for a complete one — the full message
    // still lives in Resend and in the forwarded copy.
    bodyTruncated: v.boolean(),
    // Metadata only. The bytes stay in Resend; nothing is copied into Convex
    // file storage, so these ids are the handle for fetching one on demand.
    attachments: v.array(supportEmailAttachment),
    // When Resend received the message, parsed from the webhook's ISO
    // `created_at`. `storedAt` is when this row was written.
    receivedAt: v.number(),
    storedAt: v.number(),
    // The row is inserted `pending` *before* the forward is attempted, so a
    // forward that fails still leaves the email archived and visible rather
    // than lost. `skipped` means no destination was configured, or the
    // loop guard in `support/utils.ts` refused to forward.
    forwardStatus: v.union(
        v.literal('pending'),
        v.literal('sent'),
        v.literal('skipped'),
        v.literal('failed'),
    ),
    forwardTo: v.union(v.string(), v.null()),
    forwardResendEmailId: v.union(v.string(), v.null()),
    forwardError: v.union(v.string(), v.null()),
    forwardedAt: v.union(v.number(), v.null()),
})
    .index('by_resendEmailId', ['resendEmailId'])
    .index('by_receivedAt', ['receivedAt'])
    .index('by_forwardStatus_and_receivedAt', ['forwardStatus', 'receivedAt'])
