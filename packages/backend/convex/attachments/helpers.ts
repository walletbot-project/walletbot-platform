import { isDeviceUuid } from '@wallet-bot/shared'
import type { Doc } from '../_generated/dataModel'
import type { MutationCtx } from '../_generated/server'
import {
    isFlagEnabledForUser,
    isFlagEnabledGlobally,
} from '../featureFlags/helpers'
import { attachmentRateLimiter } from './rateLimits'

/**
 * A signed-in user, or a native local account's device. The identity always
 * wins when present, so a remote account can never read or be billed as a
 * device id it also sends.
 */
export type AttachmentOwner =
    | { kind: 'user'; userId: string }
    | { kind: 'device'; deviceId: string }

export function resolveAttachmentOwner(
    userId: string | null,
    deviceId: string | undefined,
): AttachmentOwner | null {
    if (userId) return { kind: 'user', userId }
    const trimmed = deviceId?.trim()
    if (!trimmed || !isDeviceUuid(trimmed)) return null
    return { kind: 'device', deviceId: trimmed }
}

/**
 * A device has no user to carry an override, so it follows the global default,
 * and only while local accounts may use the agent at all.
 */
export async function attachmentsEnabled(
    ctx: MutationCtx,
    owner: AttachmentOwner,
): Promise<boolean> {
    if (owner.kind === 'user') {
        return isFlagEnabledForUser(ctx, 'agentAttachments', owner.userId)
    }
    return (
        (await isFlagEnabledGlobally(ctx, 'agentAttachments')) &&
        (await isFlagEnabledGlobally(ctx, 'agentLocalAccounts'))
    )
}

export function ownsAttachment(
    owner: AttachmentOwner,
    attachment: Doc<'agentAttachments'>,
): boolean {
    return owner.kind === 'user'
        ? attachment.userId === owner.userId
        : attachment.userId === undefined &&
              attachment.deviceId === owner.deviceId
}

type LimitOutcome = { ok: true } | { ok: false; retryAfter?: number }

/** Global ceiling first, then the owner's own limit, like feedback. */
export async function consumeAttachmentLimit(
    ctx: MutationCtx,
    action: 'upload' | 'read',
    owner: AttachmentOwner,
): Promise<LimitOutcome> {
    const global = await attachmentRateLimiter.limit(
        ctx,
        action === 'upload' ? 'uploadGlobal' : 'readGlobal',
    )
    if (!global.ok) return { ok: false, retryAfter: global.retryAfter }

    const scoped =
        owner.kind === 'user'
            ? await attachmentRateLimiter.limit(
                  ctx,
                  action === 'upload' ? 'uploadByUser' : 'readByUser',
                  { key: owner.userId },
              )
            : await attachmentRateLimiter.limit(
                  ctx,
                  action === 'upload' ? 'uploadByDevice' : 'readByDevice',
                  { key: owner.deviceId },
              )
    if (!scoped.ok) return { ok: false, retryAfter: scoped.retryAfter }

    return { ok: true }
}
