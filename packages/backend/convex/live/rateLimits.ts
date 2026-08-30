import { DAY, HOUR, RateLimiter } from '@convex-dev/rate-limiter'
import { components } from '../_generated/api'

/**
 * Minting is reachable by native LOCAL accounts, which are not authenticated at
 * all (the agent must work without an account — see `POST /v1/live/token`). Each
 * mint hands out a real Gemini Live token, so without these limits the endpoint
 * is an unbounded bill on the public internet.
 *
 * Three keys:
 * - `mintByUser`   — per signed-in user, the loose limit.
 * - `mintByDevice` — per native device id. That id comes from the client and is
 *   therefore spoofable, which is exactly why the global limit exists too.
 * - `mintGlobal`   — a singleton ceiling on the whole deployment, the only limit
 *   an attacker rotating device ids cannot walk around. Sharded so a burst of
 *   legitimate traffic doesn't serialize on one document.
 *
 * Token buckets rather than fixed windows because reconnects re-mint: a session
 * on a flaky network legitimately burns several tokens in a row, so each key
 * needs burst capacity above its refill rate.
 *
 * These numbers are a deliberately conservative starting point. Raise them from
 * observed usage rather than from a guess about growth.
 */
export const liveTokenRateLimiter = new RateLimiter(components.rateLimiter, {
    mintByUser: { kind: 'token bucket', rate: 300, period: DAY, capacity: 40 },
    mintByDevice: {
        kind: 'token bucket',
        rate: 100,
        period: DAY,
        capacity: 20,
    },
    mintGlobal: {
        kind: 'token bucket',
        rate: 600,
        period: HOUR,
        capacity: 600,
        shards: 5,
    },
})
