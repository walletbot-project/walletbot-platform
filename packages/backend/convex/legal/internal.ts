import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'
import { recordAcceptances } from './helpers'
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
