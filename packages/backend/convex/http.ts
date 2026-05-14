import { httpRouter } from 'convex/server'
import { internal } from './_generated/api'
import { httpAction } from './_generated/server'
import { authComponent, createAuth } from './auth'

const http = httpRouter()

// CORS handling is required for client side frameworks
authComponent.registerRoutes(http, createAuth, { cors: true })

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
