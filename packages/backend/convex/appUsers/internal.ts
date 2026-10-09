import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'
import { claimLocalAppUser, registerLocalAppUser } from './helpers'

// Only called by the live-token HTTP handler after its existing rate limit.
// There is deliberately no public endpoint for listing, linking or deleting
// identities based on these client-supplied IDs.
export const registerLocal = internalMutation({
    args: { deviceId: v.string(), localAccountId: v.string() },
    handler: (ctx, args) =>
        registerLocalAppUser(ctx, args.deviceId, args.localAccountId),
})

// Called by the native auth handlers right after they have authenticated (or
// created) the user. `createdNow` comes from the server's own observation, not
// from the request body.
export const claimLocal = internalMutation({
    args: {
        localAccountId: v.string(),
        userId: v.string(),
        createdNow: v.boolean(),
    },
    handler: (ctx, args) =>
        claimLocalAppUser(
            ctx,
            args.localAccountId,
            args.userId,
            args.createdNow,
        ),
})
