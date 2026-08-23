import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import { recordAcceptances } from '../../legal/helpers'
import { legalDocumentValidator } from '../../legal/validators'
import { requireAuth } from '../../users/helpers'

/**
 * Records the user's acceptance of the documents the gate showed them.
 *
 * `documents` is what the client displayed as needing acceptance — never wider
 * than that, so we don't record consent the user was not asked for. The
 * version written is always the server's `current`
 * (`legal/helpers.ts:recordAcceptances`), and `ageConfirmed` is mandatory: the
 * 18+ representation is part of accepting the Terms, so a client that
 * somehow submits without it is rejected rather than silently recorded.
 */
export const accept = mutation({
    args: {
        documents: v.array(legalDocumentValidator),
        ageConfirmed: v.boolean(),
        platform: v.string(),
        appVersion: v.optional(v.string()),
        locale: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await recordAcceptances(ctx, { userId, ...args })
    },
})
