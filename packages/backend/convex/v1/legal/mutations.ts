import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import { CURRENT_LEGAL_VERSION, recordAcceptance } from '../../legal/helpers'
import { requireAuth } from '../../users/helpers'

/**
 * Affirmative acceptance from the post-auth gate. The client sends the
 * version it displayed; anything but the version currently in force is
 * rejected so a stale client cannot record acceptance of superseded texts.
 */
export const accept = mutation({
    args: { documentVersion: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        if (args.documentVersion !== CURRENT_LEGAL_VERSION) {
            throw new Error('Unsupported legal documents version')
        }
        await recordAcceptance(ctx, {
            userId,
            documentVersion: args.documentVersion,
            source: 'gate',
        })
        return null
    },
})
