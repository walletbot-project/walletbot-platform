import { action } from '../../_generated/server'
import { createLiveToken } from '../../live/createToken'

/// V1 client contract for provisioning a constrained Gemini Live token.
export const requestLiveToken = action({
    args: {},
    handler: async (ctx) => {
        const startedAt = Date.now()
        const identity = await ctx.auth.getUserIdentity()
        if (!identity) {
            throw new Error('Unauthenticated')
        }

        const result = await createLiveToken()
        return {
            ...result,
            timings: {
                ...result.timings,
                actionMs: Date.now() - startedAt,
            },
        }
    },
})
