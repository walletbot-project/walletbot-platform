import { defineTable } from 'convex/server'
import { v } from 'convex/values'

/**
 * In-app feedback submissions.
 *
 * Reachable by signed-in users AND by native local-only accounts, which have no
 * backend user at all — so the submitter is recorded as EITHER `userId` or
 * `deviceId`, never both. A device row also carries `appUserId` when the
 * client named its active local account, so a row with neither `userId` nor
 * `appUserId` came from a remote account whose session had not authenticated
 * (or from a client older than that field). `platform` / `appVersion` /
 * `locale` are evidence about the client that sent it, exactly as
 * `legalAcceptances` records them.
 *
 * Attachments live in their own table (`feedbackAttachments`) rather than as an
 * array on this row, so the cleanup cron can answer "is this stored file
 * referenced?" with one indexed point-read instead of a scan.
 */
export const feedback = defineTable({
    message: v.string(),
    /** Set for a signed-in submitter. */
    userId: v.optional(v.string()),
    /** Set instead of `userId` for a native local-only account. */
    deviceId: v.optional(v.string()),
    /** `local:<localAccountId>`, client-asserted, joins with `appUsers`. */
    appUserId: v.optional(v.string()),
    /** 'web' | 'android' | 'ios' | 'macos' | 'unknown' — evidence, not a gate. */
    platform: v.string(),
    appVersion: v.optional(v.string()),
    locale: v.optional(v.string()),
    attachmentCount: v.number(),
    createdAt: v.int64(),
})
    .index('by_createdAt', ['createdAt'])
    .index('by_userId', ['userId'])
    .index('by_appUserId', ['appUserId'])

/**
 * Frontier of the orphan-attachment sweep (`feedback/internal.ts`): every stored
 * file created at or before `lastCreationTime` has already been judged — either
 * deleted as garbage or found to be referenced, which is permanent.
 *
 * A single row. Without it, the referenced files accumulating at the front of
 * the oldest-first `_storage` window would eventually fill it and the sweep
 * would never reach a newer orphan again.
 */
export const feedbackSweepState = defineTable({
    lastCreationTime: v.number(),
})

/**
 * One row per file attached to a submission.
 *
 * `size` and `contentType` are copied from the `_storage` metadata the server
 * read, never from the client. `by_storageId` is what makes the orphan cleanup
 * cron cheap (`feedback/internal.ts`).
 */
export const feedbackAttachments = defineTable({
    feedbackId: v.id('feedback'),
    storageId: v.id('_storage'),
    /** The client-supplied file name, kept for context only. */
    name: v.string(),
    size: v.number(),
    contentType: v.optional(v.string()),
})
    .index('by_feedbackId', ['feedbackId'])
    .index('by_storageId', ['storageId'])
