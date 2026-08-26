import { DAY, HOUR, RateLimiter } from '@convex-dev/rate-limiter'
import { components } from '../_generated/api'

/**
 * Feedback is reachable by native LOCAL accounts, which are not authenticated
 * at all — so `v1/feedback/mutations` is a publicly callable mutation that
 * hands out Convex upload URLs. Without these limits it is an unbounded storage
 * amplifier (10 files x 100 MB per submission).
 *
 * Three keys per action:
 * - `*ByUser`   — per signed-in user, the loose limit.
 * - `*ByDevice` — per native device id. That id comes from the client and is
 *   therefore spoofable, which is exactly why the global limit exists too.
 * - `*Global`   — a singleton ceiling on the whole deployment, the only limit an
 *   attacker rotating device ids cannot walk around. Sharded so a burst of
 *   legitimate traffic doesn't serialize on one document.
 *
 * A submission consumes up to `FEEDBACK_MAX_ATTACHMENTS` upload URLs, so every
 * upload limit is ~10x its submit counterpart plus headroom: a 100 MB POST has
 * a hard 2-minute timeout server-side, and a retry needs a fresh URL.
 */
export const feedbackRateLimiter = new RateLimiter(components.rateLimiter, {
    submitByUser: { kind: 'fixed window', rate: 10, period: DAY },
    submitByDevice: { kind: 'fixed window', rate: 2, period: DAY },
    submitGlobal: { kind: 'fixed window', rate: 200, period: HOUR, shards: 5 },
    uploadByUser: {
        kind: 'token bucket',
        rate: 120,
        period: DAY,
        capacity: 30,
    },
    uploadByDevice: {
        kind: 'token bucket',
        rate: 30,
        period: DAY,
        capacity: 12,
    },
    uploadGlobal: {
        kind: 'token bucket',
        rate: 2000,
        period: HOUR,
        capacity: 2000,
        shards: 5,
    },
})
