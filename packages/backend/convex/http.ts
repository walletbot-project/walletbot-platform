import { httpRouter } from 'convex/server'
import { internal } from './_generated/api'
import { httpAction } from './_generated/server'
import { authComponent, createAuth } from './auth'
import { registerAuthNativeRoutes } from './authNative/http'
import { registerConfigRoutes } from './config/http'

const http = httpRouter()

// CORS handling is required for client side frameworks
authComponent.registerRoutes(http, createAuth, { cors: true })

// Native app auth: Google idToken → mint our own JWT + rotating refresh token.
registerAuthNativeRoutes(http)

// Versioned native config surface:
// - `/v1/config` = device/client-version layer (unauthenticated)
// - `/v1/account-config` = account layer (remote session token or local label)
registerConfigRoutes(http)

http.route({
    path: '/api/live/token',
    method: 'POST',
    handler: httpAction(async (ctx) => {
        const result = await ctx.runAction(
            internal.live.actions.requestLiveTokenForHttp,
            {},
        )

        return new Response(JSON.stringify(result), {
            status: 200,
            headers: {
                'content-type': 'application/json',
                'access-control-allow-origin': '*',
            },
        })
    }),
})

export default http
