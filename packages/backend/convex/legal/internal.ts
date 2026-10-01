import { v } from 'convex/values'
import { internalMutation, internalQuery } from '../_generated/server'
import {
    type AiConsentStatus,
    recordAcceptances,
    resolveAiConsent,
} from './helpers'
import { acceptanceInputValidator } from './validators'

/**
 * Records an acceptance for a user id resolved outside a mutation.
 *
 * Used by the sign-up HTTP endpoint (`authNative/http.ts`): email sign-up
 * creates the account but mints no session (email verification is required),
 * so there is no authenticated caller to run `v1/legal/mutations:accept`. The
 * endpoint resolves the freshly created user itself and calls this.
 */
export const recordAcceptancesForUser = internalMutation({
    args: {
        userId: v.string(),
        acceptance: acceptanceInputValidator,
    },
    handler: async (ctx, { userId, acceptance }) => {
        await recordAcceptances(ctx, { userId, ...acceptance })
    },
})

/**
 * The AI-consent verdict for a user id, for callers that are not queries.
 *
 * `v1/live/actions.ts` mints the agent token from an action, where the
 * `requireAuth` helpers and `ctx.db` are both out of reach, so it reads the
 * verdict through here.
 */
export const aiConsentForUser = internalQuery({
    args: { userId: v.string() },
    handler: async (ctx, { userId }): Promise<AiConsentStatus> =>
        await resolveAiConsent(ctx, userId),
})
