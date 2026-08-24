import type { MutationCtx } from '../_generated/server'
import { getOptionalUserId } from '../users/helpers'
import { feedbackRateLimiter } from './rateLimits'
import { MAX_DEVICE_ID_LENGTH } from './utils'

/**
 * Who is submitting: a signed-in user, or an unauthenticated native device.
 *
 * The identity always wins when one is present, so a remote account can never
 * be billed against (or hide behind) a device key it also sends.
 */
export type Submitter =
    | { kind: 'user'; userId: string }
    | { kind: 'device'; deviceId: string }

export async function resolveSubmitter(
    ctx: MutationCtx,
    deviceId: string | undefined,
): Promise<Submitter | null> {
    const userId = await getOptionalUserId(ctx)
    if (userId) return { kind: 'user', userId }

    const trimmed = deviceId?.trim()
    if (!trimmed || trimmed.length > MAX_DEVICE_ID_LENGTH) return null
    return { kind: 'device', deviceId: trimmed }
}

type LimitOutcome = { ok: true } | { ok: false; retryAfter?: number }

/**
 * Consumes the global limit plus the submitter's own, for one of the two
 * actions. The global one is checked first: an attacker rotating device ids is
 * stopped there, and a legitimate user never reaches it.
 */
export async function consumeFeedbackLimit(
    ctx: MutationCtx,
    action: 'submit' | 'upload',
    submitter: Submitter,
): Promise<LimitOutcome> {
    const global = await feedbackRateLimiter.limit(
        ctx,
        action === 'submit' ? 'submitGlobal' : 'uploadGlobal',
    )
    if (!global.ok) return { ok: false, retryAfter: global.retryAfter }

    const scoped =
        submitter.kind === 'user'
            ? await feedbackRateLimiter.limit(
                  ctx,
                  action === 'submit' ? 'submitByUser' : 'uploadByUser',
                  { key: submitter.userId },
              )
            : await feedbackRateLimiter.limit(
                  ctx,
                  action === 'submit' ? 'submitByDevice' : 'uploadByDevice',
                  { key: submitter.deviceId },
              )
    if (!scoped.ok) return { ok: false, retryAfter: scoped.retryAfter }

    return { ok: true }
}
