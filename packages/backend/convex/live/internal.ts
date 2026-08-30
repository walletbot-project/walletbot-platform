import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'
import { isFlagEnabledGlobally } from '../featureFlags/helpers'
import { type LiveMintGate, resolveLiveSubmitter } from './helpers'
import { liveTokenRateLimiter } from './rateLimits'

/**
 * Consumes the mint limits for one live-token request.
 *
 * Both callers are actions (the Convex action and the HTTP route), which cannot
 * reach the rate limiter directly, so each resolves identity its own way and
 * passes the result in. Trusting an explicit `userId` is safe only because this
 * is an internal mutation and therefore unreachable from a client.
 */
export const consumeMintLimit = internalMutation({
    args: {
        userId: v.optional(v.string()),
        deviceId: v.optional(v.string()),
    },
    handler: async (ctx, args): Promise<LiveMintGate> => {
        const submitter = resolveLiveSubmitter(
            args.userId ?? null,
            args.deviceId,
        )
        if (!submitter) return { ok: false, error: 'unidentified_client' }

        // The kill switch for the unauthenticated path, checked before any
        // limit is consumed so a disabled rollout never spends the shared
        // budget. Resolved globally: a device caller has no user to carry an
        // override.
        if (
            submitter.kind === 'device' &&
            !(await isFlagEnabledGlobally(ctx, 'agentLocalAccounts'))
        ) {
            return { ok: false, error: 'local_accounts_disabled' }
        }

        // The global one is checked first: an attacker rotating device ids is
        // stopped there, and a legitimate caller never reaches it.
        const global = await liveTokenRateLimiter.limit(ctx, 'mintGlobal')
        if (!global.ok) {
            return {
                ok: false,
                error: 'rate_limited',
                retryAfter: global.retryAfter,
            }
        }

        const scoped =
            submitter.kind === 'user'
                ? await liveTokenRateLimiter.limit(ctx, 'mintByUser', {
                      key: submitter.userId,
                  })
                : await liveTokenRateLimiter.limit(ctx, 'mintByDevice', {
                      key: submitter.deviceId,
                  })
        if (!scoped.ok) {
            return {
                ok: false,
                error: 'rate_limited',
                retryAfter: scoped.retryAfter,
            }
        }

        return { ok: true }
    },
})
