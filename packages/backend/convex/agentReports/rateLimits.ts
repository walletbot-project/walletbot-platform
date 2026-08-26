import { DAY, HOUR, RateLimiter } from '@convex-dev/rate-limiter'
import { components } from '../_generated/api'

/**
 * Reports are reachable by native LOCAL accounts, which are not authenticated at
 * all, so `v1/agentReports/mutations:submit` is a publicly callable mutation
 * that writes a row carrying up to two 4000-character snapshots. Without these
 * limits it is an unbounded write amplifier.
 *
 * The three keys mirror `feedback/rateLimits.ts`:
 * - `submitByUser`   — per signed-in user, the loose limit.
 * - `submitByDevice` — per native device id. That id comes from the client and
 *   is therefore spoofable, which is exactly why the global limit exists too.
 * - `submitGlobal`   — a singleton ceiling on the whole deployment, the only
 *   limit an attacker rotating device ids cannot walk around. Sharded so a
 *   burst of legitimate traffic doesn't serialize on one document.
 *
 * Looser than feedback's, because a report is a safety signal and suppressing a
 * genuine one is worse than absorbing a few duplicates. There is no upload
 * counterpart: reports carry no attachments at all.
 */
export const agentReportRateLimiter = new RateLimiter(components.rateLimiter, {
    submitByUser: { kind: 'fixed window', rate: 20, period: DAY },
    submitByDevice: { kind: 'fixed window', rate: 5, period: DAY },
    submitGlobal: { kind: 'fixed window', rate: 300, period: HOUR, shards: 5 },
})
