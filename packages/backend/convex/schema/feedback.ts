import { defineTable } from 'convex/server'
import { v } from 'convex/values'

/**
 * One row per in-app feedback submission: a written report plus any files the
 * user attached. Written only by `v1/feedback/mutations:submit`.
 *
 * Not a synced table: it never reaches a native or web client through
 * `v1/sync`, so it forces no sync-contract or drift schema bump (same
 * reasoning as `supportEmails`).
 *
 * `userId` is null for a submission from a native local-only account. Those
 * accounts have no backend user at all, so anonymous feedback is the only kind
 * they can send — and `submit` is deliberately reachable without auth for
 * exactly that case. The field is resolved from `ctx.auth.getUserIdentity()`
 * server-side and is never accepted from the client.
 */
export const feedbackAttachment = v.object({
    storageId: v.id('_storage'),
    // Whatever the picker reported. Cosmetic only — used to label the file when
    // reading the submission back, never to decide anything.
    filename: v.union(v.string(), v.null()),
    contentType: v.union(v.string(), v.null()),
    // Read back off the `_storage` system table at submit time, not taken from
    // the client, so it reflects the bytes actually stored.
    size: v.number(),
})

export const feedback = defineTable({
    // Null = anonymous (native local-only account). Never client-supplied.
    userId: v.union(v.string(), v.null()),
    text: v.string(),
    attachments: v.array(feedbackAttachment),
    // Client identity for triage: which build the report came from. Advisory
    // only — a client can claim anything here, so nothing is authorized on it.
    platform: v.string(),
    appVersion: v.string(),
    // The rate-limit subject. Kept on the row so an abusive install can be
    // identified after the fact; it is a random per-install UUID
    // (`apps/native/lib/app_config/device_id.dart`), not a hardware id.
    deviceId: v.union(v.string(), v.null()),
    locale: v.union(v.string(), v.null()),
    submittedAt: v.number(),
})
    .index('by_submittedAt', ['submittedAt'])
    .index('by_user_and_submittedAt', ['userId', 'submittedAt'])
