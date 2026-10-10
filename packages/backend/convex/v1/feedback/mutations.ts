import { v } from 'convex/values'
import type { Id } from '../../_generated/dataModel'
import { type MutationCtx, mutation } from '../../_generated/server'
import {
    consumeFeedbackLimit,
    resolveSubmitter,
    submitterFields,
} from '../../feedback/helpers'
import {
    FEEDBACK_MAX_ATTACHMENT_BYTES,
    FEEDBACK_MAX_ATTACHMENTS,
    FEEDBACK_MAX_MESSAGE_LENGTH,
    type FeedbackResult,
    MAX_ATTACHMENT_NAME_LENGTH,
    type UploadUrlResult,
} from '../../feedback/utils'

/**
 * V1 in-app feedback contract.
 *
 * Deliberately callable WITHOUT authentication: native local-only accounts have
 * no backend user, and they must be able to report problems. An unauthenticated
 * caller identifies itself with `deviceId` and gets the tighter rate limits in
 * `feedback/rateLimits.ts`; a signed-in caller's identity always wins over any
 * `deviceId` it also sends. A local account also sends its `localAccountId`,
 * stored as `appUserId` so its submissions can be told apart from a remote
 * account whose session had not authenticated yet.
 *
 * Files never travel through a Convex function. The client asks for an upload
 * URL, POSTs the bytes straight to it, and sends back only the resulting storage
 * ids — so `submit` first meets an attachment as `_storage` metadata, which is
 * also the only place its real size can be trusted.
 */

const attachmentArg = v.object({
    // `v.string()`, not `v.id('_storage')`: this comes from an untrusted client,
    // so a malformed id must be a clean rejection rather than an argument
    // validation error. Normalized below.
    storageId: v.string(),
    name: v.string(),
})

const clientArgs = {
    platform: v.string(),
    appVersion: v.optional(v.string()),
    locale: v.optional(v.string()),
    /** Required when the caller has no identity (native local account). */
    deviceId: v.optional(v.string()),
    /** The active local account, for attribution only. */
    localAccountId: v.optional(v.string()),
}

export const generateAttachmentUploadUrl = mutation({
    args: { deviceId: v.optional(v.string()) },
    handler: async (ctx, args): Promise<UploadUrlResult> => {
        const submitter = await resolveSubmitter(ctx, args.deviceId)
        if (!submitter) return { ok: false, error: 'unidentified_client' }

        const limit = await consumeFeedbackLimit(ctx, 'upload', submitter)
        if (!limit.ok) {
            return {
                ok: false,
                error: 'rate_limited',
                retryAfter: limit.retryAfter,
            }
        }

        return { ok: true, uploadUrl: await ctx.storage.generateUploadUrl() }
    },
})

export const submit = mutation({
    args: {
        message: v.string(),
        attachments: v.array(attachmentArg),
        ...clientArgs,
    },
    handler: async (ctx, args): Promise<FeedbackResult> => {
        const submitter = await resolveSubmitter(
            ctx,
            args.deviceId,
            args.localAccountId,
        )
        if (!submitter) return { ok: false, error: 'unidentified_client' }

        // Validated BEFORE the limit is consumed: a rejected submission writes
        // nothing, so charging a token for it would only cost a real user one of
        // their few daily attempts (a local account has two). Abuse is still
        // bounded — nothing accumulates until the limit passes below, and the
        // attachments themselves came through the rate-limited upload path.
        const message = args.message.trim()
        if (!message || message.length > FEEDBACK_MAX_MESSAGE_LENGTH) {
            return { ok: false, error: 'message_invalid' }
        }

        const attachments = await resolveAttachments(ctx, args.attachments)
        if (!attachments) return { ok: false, error: 'attachment_invalid' }

        const limit = await consumeFeedbackLimit(ctx, 'submit', submitter)
        if (!limit.ok) {
            return {
                ok: false,
                error: 'rate_limited',
                retryAfter: limit.retryAfter,
            }
        }

        const feedbackId = await ctx.db.insert('feedback', {
            message,
            ...submitterFields(submitter),
            platform: args.platform,
            appVersion: args.appVersion,
            locale: args.locale,
            attachmentCount: attachments.length,
            createdAt: BigInt(Date.now()),
        })

        for (const attachment of attachments) {
            await ctx.db.insert('feedbackAttachments', {
                feedbackId,
                ...attachment,
            })
        }

        return { ok: true }
    },
})

type ResolvedAttachment = {
    storageId: Id<'_storage'>
    name: string
    size: number
    contentType?: string
}

/**
 * Validates the storage ids the client sent and reads each file's real metadata.
 * Returns `null` on the first problem — the caller turns that into a single
 * `attachment_invalid`.
 *
 * Nothing is deleted on rejection: a caller could name a stored file it did not
 * upload, and deleting it here would let one client destroy another's in-flight
 * attachment. Whatever ends up unreferenced is reclaimed by
 * `feedback/internal.ts:deleteOrphanAttachments`.
 */
async function resolveAttachments(
    ctx: MutationCtx,
    input: readonly { storageId: string; name: string }[],
): Promise<ResolvedAttachment[] | null> {
    if (input.length > FEEDBACK_MAX_ATTACHMENTS) return null

    const seen = new Set<string>()
    const resolved: ResolvedAttachment[] = []
    for (const attachment of input) {
        const storageId = ctx.db.system.normalizeId(
            '_storage',
            attachment.storageId,
        )
        if (!storageId || seen.has(storageId)) return null
        seen.add(storageId)

        const metadata = await ctx.db.system.get('_storage', storageId)
        if (!metadata || metadata.size > FEEDBACK_MAX_ATTACHMENT_BYTES) {
            return null
        }

        const name = attachment.name.trim().slice(0, MAX_ATTACHMENT_NAME_LENGTH)
        resolved.push({
            storageId,
            name: name || storageId,
            size: metadata.size,
            ...(metadata.contentType
                ? { contentType: metadata.contentType }
                : {}),
        })
    }
    return resolved
}
