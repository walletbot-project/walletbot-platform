import type { AttachmentKind } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internal } from '../_generated/api'
import type { Id } from '../_generated/dataModel'
import { internalMutation } from '../_generated/server'
import {
    attachmentsEnabled,
    consumeAttachmentLimit,
    ownsAttachment,
    resolveAttachmentOwner,
} from './helpers'
import type { AttachmentReadError } from './utils'

export type BeginReadResult =
    | {
          ok: true
          attachment: {
              storageId: Id<'_storage'>
              name: string
              kind: AttachmentKind
              contentType: string
          }
      }
    | { ok: false; code: AttachmentReadError; retryAfter?: number }

/**
 * Everything a read must pass before the paid model call, in one transaction:
 * identity, the flag, ownership, expiry, then the rate limit. Trusting an
 * explicit `userId` is safe only because this is internal; the public action
 * derives it from `ctx.auth`.
 *
 * A foreign or unknown id both come back `not_found`, so ids cannot be probed.
 * The limit is consumed last, so a bad id costs the caller nothing.
 */
export const beginRead = internalMutation({
    args: {
        userId: v.optional(v.string()),
        deviceId: v.optional(v.string()),
        attachmentId: v.string(),
    },
    handler: async (ctx, args): Promise<BeginReadResult> => {
        const owner = resolveAttachmentOwner(args.userId ?? null, args.deviceId)
        if (!owner) return { ok: false, code: 'unidentified_client' }
        if (!(await attachmentsEnabled(ctx, owner))) {
            return { ok: false, code: 'feature_disabled' }
        }

        const id = ctx.db.normalizeId('agentAttachments', args.attachmentId)
        const attachment = id ? await ctx.db.get('agentAttachments', id) : null
        if (!attachment || !ownsAttachment(owner, attachment)) {
            return { ok: false, code: 'not_found' }
        }
        if (attachment.expiresAt <= Date.now()) {
            return { ok: false, code: 'expired' }
        }
        const file = await ctx.db.system.get('_storage', attachment.storageId)
        if (!file) return { ok: false, code: 'expired' }

        const limit = await consumeAttachmentLimit(ctx, 'read', owner)
        if (!limit.ok) {
            return limit.retryAfter === undefined
                ? { ok: false, code: 'rate_limited' }
                : {
                      ok: false,
                      code: 'rate_limited',
                      retryAfter: limit.retryAfter,
                  }
        }

        return {
            ok: true,
            attachment: {
                storageId: attachment.storageId,
                name: attachment.name,
                kind: attachment.kind,
                contentType: attachment.contentType,
            },
        }
    },
})

/**
 * Deletes expired attachments and their files, oldest first, rescheduling
 * itself while a full batch comes back.
 */
export const deleteExpired = internalMutation({
    args: { limit: v.number() },
    handler: async (ctx, args) => {
        const expired = await ctx.db
            .query('agentAttachments')
            .withIndex('by_expiresAt', (q) => q.lte('expiresAt', Date.now()))
            .take(args.limit)

        for (const attachment of expired) {
            if (await ctx.db.system.get('_storage', attachment.storageId)) {
                await ctx.storage.delete(attachment.storageId)
            }
            await ctx.db.delete('agentAttachments', attachment._id)
        }

        if (expired.length === args.limit) {
            await ctx.scheduler.runAfter(
                0,
                internal.attachments.internal.deleteExpired,
                args,
            )
        }
        return { deleted: expired.length }
    },
})
