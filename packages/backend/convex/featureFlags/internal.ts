import { v } from 'convex/values'
import { internalQuery } from '../_generated/server'
import { resolveFlagsForUser } from './helpers'

// Used by config/http.ts's account-config httpAction, which runs in ActionCtx
// and has no direct `ctx.db` access.
export const resolveFlagsForUserInternal = internalQuery({
    args: { userId: v.union(v.string(), v.null()) },
    handler: async (ctx, args) => {
        return await resolveFlagsForUser(ctx, args.userId)
    },
})
