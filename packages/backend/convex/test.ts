import { query } from './_generated/server'

// Dummy query used by the native app to verify Convex JWT auth end-to-end.
export const hello = query({
    args: {},
    handler: async (ctx) => {
        const identity = await ctx.auth.getUserIdentity()

        console.log('hello query called with identity', identity)

        return {
            authenticated: identity !== null,
            subject: identity?.subject ?? null,
            email: identity?.email ?? null,
            now: Date.now(),
        }
    },
})
