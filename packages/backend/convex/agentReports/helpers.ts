import type { MutationCtx } from '../_generated/server'
import type { Submitter } from '../feedback/helpers'
import { agentReportRateLimiter } from './rateLimits'

type LimitOutcome = { ok: true } | { ok: false; retryAfter?: number }

/**
 * Consumes the global limit plus the reporter's own. The global one is checked
 * first: an attacker rotating device ids is stopped there, and a legitimate
 * reporter never reaches it.
 *
 * The reporter itself is resolved by `feedback/helpers:resolveSubmitter` — both
 * surfaces are callable without authentication and identify the caller exactly
 * the same way, so there is one implementation of that rule, not two.
 */
export async function consumeAgentReportLimit(
    ctx: MutationCtx,
    submitter: Submitter,
): Promise<LimitOutcome> {
    const global = await agentReportRateLimiter.limit(ctx, 'submitGlobal')
    if (!global.ok) return { ok: false, retryAfter: global.retryAfter }

    const scoped =
        submitter.kind === 'user'
            ? await agentReportRateLimiter.limit(ctx, 'submitByUser', {
                  key: submitter.userId,
              })
            : await agentReportRateLimiter.limit(ctx, 'submitByDevice', {
                  key: submitter.deviceId,
              })
    if (!scoped.ok) return { ok: false, retryAfter: scoped.retryAfter }

    return { ok: true }
}
