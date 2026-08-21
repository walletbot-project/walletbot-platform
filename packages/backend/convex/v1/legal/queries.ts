import { query } from '../../_generated/server'
import {
    CURRENT_LEGAL_VERSION,
    getCurrentAcceptance,
} from '../../legal/helpers'
import { requireAuth } from '../../users/helpers'

/**
 * Whether the authenticated user has accepted the legal documents version
 * currently in force. `accepted: false` drives the blocking acceptance gate
 * on both clients.
 */
export const getMyAcceptance = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        const acceptance = await getCurrentAcceptance(ctx, userId)
        return {
            currentVersion: CURRENT_LEGAL_VERSION,
            accepted: acceptance !== null,
            acceptedAt: acceptance?.acceptedAt ?? null,
        }
    },
})
