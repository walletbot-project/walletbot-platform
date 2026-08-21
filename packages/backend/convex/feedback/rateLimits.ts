import {
    HOUR,
    RateLimiter,
    type RunMutationCtx,
} from '@convex-dev/rate-limiter'
import { components } from '../_generated/api'

/**
 * `v1/feedback/mutations` are reachable **without authentication**, because a
 * native local-only account has no backend user and must still be able to send
 * feedback (CLAUDE.md § offline-first: a local account is a first-class
 * account). That makes both of them public ingress, so they are rate limited
 * on two axes:
 *
 * - **Per device.** Bounds the ordinary case — a stuck submit button, a user
 *   hammering "send", one misbehaving install. The key is the client-supplied
 *   `deviceId`, a random per-install UUID
 *   (`apps/native/lib/app_config/device_id.dart`).
 *
 * - **Globally.** `deviceId` comes from the client, so an abuser who rotates it
 *   walks straight through the per-device limit. The global buckets are the
 *   backstop that bounds total anonymous ingress however many identities are
 *   forged. They are shared across every caller, so they are sized well above
 *   real aggregate usage — they exist to cap a flood, not to shape normal
 *   traffic.
 *
 * `uploadUrl` is limited more loosely than `submit` because one submission
 * needs up to `FEEDBACK_MAX_FILES` of them, but it is the more dangerous of
 * the two: it hands out an ingress URL for bytes, where `submit` only writes a
 * row. Both are `token bucket` rather than `fixed window` so picking five
 * attachments at once is not punished by a window boundary, while the
 * sustained rate stays bounded.
 */
export const feedbackRateLimiter = new RateLimiter(components.rateLimiter, {
    // ~20/hour per install: four full 5-file submissions, with headroom to
    // retry a failed upload.
    feedbackUploadUrlPerDevice: {
        kind: 'token bucket',
        rate: 20,
        period: HOUR,
        capacity: 10,
    },
    // Feedback is not something a person sends continuously.
    feedbackSubmitPerDevice: {
        kind: 'token bucket',
        rate: 5,
        period: HOUR,
        capacity: 5,
    },
    // Global backstops, sized to absorb a genuine spike (a bad release
    // generating real reports) while refusing a sustained flood from rotated
    // device ids.
    feedbackUploadUrlGlobal: {
        kind: 'token bucket',
        rate: 600,
        period: HOUR,
        capacity: 120,
    },
    feedbackSubmitGlobal: {
        kind: 'token bucket',
        rate: 300,
        period: HOUR,
        capacity: 60,
    },
})

/** `null` when the caller may proceed, otherwise the wait in milliseconds. */
export type RateLimitVerdict = { retryAfterMs: number } | null

/**
 * Applies the global backstop, then the per-device limit. Both must pass.
 *
 * `limit()` consumes a token and reports the verdict rather than throwing, so
 * a refusal is returned here and turned into `{ ok: false, error:
 * 'rate_limited' }` by the caller — never swallowed into a fake success.
 */
export async function checkFeedbackLimit(
    ctx: RunMutationCtx,
    kind: 'uploadUrl' | 'submit',
    deviceId: string | null,
): Promise<RateLimitVerdict> {
    const global =
        kind === 'uploadUrl'
            ? 'feedbackUploadUrlGlobal'
            : 'feedbackSubmitGlobal'
    const perDevice =
        kind === 'uploadUrl'
            ? 'feedbackUploadUrlPerDevice'
            : 'feedbackSubmitPerDevice'

    const globalVerdict = await feedbackRateLimiter.limit(ctx, global)
    if (!globalVerdict.ok) return { retryAfterMs: globalVerdict.retryAfter }

    // A caller that sends no deviceId is not exempt — it shares one bucket,
    // which is strictly harsher than having an identity of its own.
    const deviceVerdict = await feedbackRateLimiter.limit(ctx, perDevice, {
        key: deviceId ?? 'unknown-device',
    })
    if (!deviceVerdict.ok) return { retryAfterMs: deviceVerdict.retryAfter }

    return null
}
