import { legalVerdict } from '@wallet-bot/shared'
import { query } from '../../_generated/server'
import { getLatestAcceptance, LEGAL_POLICY } from '../../legal/helpers'
import { requireAuth } from '../../users/helpers'

/**
 * Acceptance verdict for the authenticated user. The server owns the policy
 * (packages/shared/src/legal.ts) and returns only the decision plus display
 * data, so enforcement changes are a backend deploy — installed clients just
 * render. Client contract: `reacceptRequired` is the ONLY blocking status;
 * anything unrecognized degrades to the dismissible prompt.
 *
 * `Date.now()` here means a grace expiry flips on the query's next
 * re-evaluation (any refetch, reconnect or app open), not the exact instant
 * it passes — acceptable for a multi-day notice window.
 */
export const getMyAcceptance = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        const latest = await getLatestAcceptance(ctx, userId)
        const acceptedVersion = latest?.documentVersion ?? null
        return {
            status: legalVerdict(acceptedVersion, LEGAL_POLICY, Date.now()),
            currentVersion: LEGAL_POLICY.currentVersion,
            graceEndsAt: LEGAL_POLICY.graceEndsAt,
            acceptedVersion,
            // Plain number, not the int64 it is stored as: the Convex wire
            // encodes bigints as objects, which no client here can read.
            acceptedAt: latest ? Number(latest.acceptedAt) : null,
        }
    },
})

/**
 * The policy alone, with no user attached — deliberately public, because the
 * sign-up form needs the version it is about to record BEFORE there is an
 * account, and this is the same policy `/v1/config` already serves
 * unauthenticated to native clients.
 */
export const getPolicy = query({
    args: {},
    handler: async () => LEGAL_POLICY,
})
