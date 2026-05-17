import { ConvexError } from 'convex/values'
import { query } from './_generated/server'
import { authComponent } from './auth'

// Dummy query used by the native app to verify Convex JWT auth end-to-end.
export const hello = query({
    args: {},
    handler: async (ctx) => {
        const identity = await ctx.auth.getUserIdentity()
        if (!identity) {
            throw new ConvexError('Unauthenticated')
        }
        const user = await authComponent.getAnyUserById(ctx, identity.subject)
        if (!user) {
            throw new ConvexError('User not recognized')
        }
        return {
            subject: identity.subject,
            email: user.email,
            name: user.name,
            now: Date.now(),
        }
    },
})
