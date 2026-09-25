import { DAY, HOUR, RateLimiter } from '@convex-dev/rate-limiter'
import { components } from '../_generated/api'

/**
 * Attachments are reachable by native LOCAL accounts, which are not
 * authenticated, so both the upload URL and the read (a paid OpenAI call) are
 * public entry points. Same three-key shape as `feedback/rateLimits.ts`: a
 * loose per-user limit, a tighter per-device one (spoofable, hence the third),
 * and a sharded global ceiling that rotating device ids cannot walk around.
 */
export const attachmentRateLimiter = new RateLimiter(components.rateLimiter, {
    uploadByUser: {
        kind: 'token bucket',
        rate: 100,
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
    readByUser: {
        kind: 'token bucket',
        rate: 200,
        period: DAY,
        capacity: 40,
    },
    readByDevice: {
        kind: 'token bucket',
        rate: 60,
        period: DAY,
        capacity: 20,
    },
    readGlobal: {
        kind: 'token bucket',
        rate: 1000,
        period: HOUR,
        capacity: 1000,
        shards: 5,
    },
})
