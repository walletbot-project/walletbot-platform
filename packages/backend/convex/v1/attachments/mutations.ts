import {
    ATTACHMENT_MAX_BYTES,
    ATTACHMENT_MAX_NAME_LENGTH,
    ATTACHMENT_TTL_MS,
    attachmentTypeForMime,
} from '@wallet-bot/shared'
import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import {
    attachmentsEnabled,
    consumeAttachmentLimit,
    resolveAttachmentOwner,
} from '../../attachments/helpers'
import type { RegisterResult, UploadUrlResult } from '../../attachments/utils'
import { getOptionalUserId } from '../../users/helpers'

/**
 * V1 agent chat attachments.
 *
 * Callable WITHOUT authentication, like `v1/feedback`: native local accounts
 * have no backend user and identify themselves with their device id. Files
 * never travel through a Convex function: the client POSTs the bytes to the
 * upload URL and registers the resulting storage id, so the server first meets
 * the file as `_storage` metadata, the only place its size can be trusted.
 */

export const generateUploadUrl = mutation({
    args: { deviceId: v.optional(v.string()) },
    handler: async (ctx, args): Promise<UploadUrlResult> => {
        const owner = resolveAttachmentOwner(
            await getOptionalUserId(ctx),
            args.deviceId,
        )
        if (!owner) return { ok: false, error: 'unidentified_client' }
        if (!(await attachmentsEnabled(ctx, owner))) {
            return { ok: false, error: 'feature_disabled' }
        }

        const limit = await consumeAttachmentLimit(ctx, 'upload', owner)
        if (!limit.ok) {
            return limit.retryAfter === undefined
                ? { ok: false, error: 'rate_limited' }
                : {
                      ok: false,
                      error: 'rate_limited',
                      retryAfter: limit.retryAfter,
                  }
        }

        return { ok: true, uploadUrl: await ctx.storage.generateUploadUrl() }
    },
})

export const register = mutation({
    args: {
        // `v.string()`, not `v.id('_storage')`: a malformed id from an
        // untrusted client must be a clean rejection, not a validation error.
        storageId: v.string(),
        name: v.string(),
        deviceId: v.optional(v.string()),
    },
    handler: async (ctx, args): Promise<RegisterResult> => {
        const owner = resolveAttachmentOwner(
            await getOptionalUserId(ctx),
            args.deviceId,
        )
        if (!owner) return { ok: false, error: 'unidentified_client' }
        if (!(await attachmentsEnabled(ctx, owner))) {
            return { ok: false, error: 'feature_disabled' }
        }

        const storageId = ctx.db.system.normalizeId('_storage', args.storageId)
        if (!storageId) return { ok: false, error: 'invalid_file' }
        const metadata = await ctx.db.system.get('_storage', storageId)
        if (!metadata || metadata.size === 0) {
            return { ok: false, error: 'invalid_file' }
        }

        // A stored file backs at most one attachment and never a feedback
        // submission. Refusing reuse is what stops a caller from registering,
        // and then reading, a file someone else uploaded. Nothing is deleted
        // on rejection for the same reason; the orphan sweep reclaims it.
        const claimed =
            (await ctx.db
                .query('agentAttachments')
                .withIndex('by_storageId', (q) => q.eq('storageId', storageId))
                .first()) ??
            (await ctx.db
                .query('feedbackAttachments')
                .withIndex('by_storageId', (q) => q.eq('storageId', storageId))
                .first())
        if (claimed) return { ok: false, error: 'invalid_file' }

        const type = attachmentTypeForMime(metadata.contentType)
        if (!type) return { ok: false, error: 'unsupported_type' }
        if (metadata.size > ATTACHMENT_MAX_BYTES[type.kind]) {
            return { ok: false, error: 'too_large' }
        }

        const name =
            args.name.trim().slice(0, ATTACHMENT_MAX_NAME_LENGTH) ||
            'attachment'
        const expiresAt = Date.now() + ATTACHMENT_TTL_MS
        const attachmentId = await ctx.db.insert('agentAttachments', {
            ...(owner.kind === 'user'
                ? { userId: owner.userId }
                : { deviceId: owner.deviceId }),
            storageId,
            name,
            kind: type.kind,
            contentType: type.mimeType,
            size: metadata.size,
            expiresAt,
        })

        return { ok: true, attachmentId, kind: type.kind, expiresAt }
    },
})
