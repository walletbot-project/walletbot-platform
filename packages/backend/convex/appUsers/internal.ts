import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'
import { acceptanceInputValidator } from '../legal/validators'
import {
    applyPromotionCarryover,
    claimLocalAppUser,
    registerLocalAppUser,
} from './helpers'

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

// Called by the native auth handlers once a promotion has been accepted, with
// the user the local account was linked to. See `applyPromotionCarryover`.
export const applyCarryover = internalMutation({
    args: {
        userId: v.string(),
        acceptance: v.optional(acceptanceInputValidator),
        aiConsent: v.optional(
            v.object({
                platform: v.string(),
                appVersion: v.optional(v.string()),
                locale: v.optional(v.string()),
            }),
        ),
        defaultCurrency: v.optional(v.string()),
    },
    handler: (ctx, { userId, ...carryover }) =>
        applyPromotionCarryover(ctx, userId, carryover),
})
