'use node'

import { action, internalAction } from '../../_generated/server'
import { createLiveToken } from '../../live/createToken'

/// V1 client contract for provisioning a constrained Gemini Live token.
export const requestLiveToken = action({
    args: {},
    handler: async (ctx) => {
        const identity = await ctx.auth.getUserIdentity()
        if (!identity) {
            throw new Error('Unauthenticated')
        }

        return createLiveToken()
    },
})

/// Internal bridge used by the versioned HTTP token endpoint.
export const requestLiveTokenForHttp = internalAction({
    args: {},
    handler: async () => createLiveToken(),
})
