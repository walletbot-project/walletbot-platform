import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'
import { registerLocalAppUser } from './helpers'

// Only called by the live-token HTTP handler after its existing rate limit.
// There is deliberately no public endpoint for listing, linking or deleting
// identities based on these client-supplied IDs.
export const registerLocal = internalMutation({
    args: { deviceId: v.string(), localAccountId: v.string() },
    handler: (ctx, args) =>
        registerLocalAppUser(ctx, args.deviceId, args.localAccountId),
})
