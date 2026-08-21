import { httpRouter } from 'convex/server'
import { internal } from './_generated/api'
import { httpAction } from './_generated/server'
import { authComponent, createAuth } from './auth'
import { registerAuthNativeRoutes } from './authNative/http'
import { hashSessionSecret } from './authNative/utils'
import { registerConfigRoutes } from './config/http'
import { resend } from './emails/helpers'
import { jsonResponse } from './httpHelpers'
import { registerSupportRoutes } from './support/http'
import { registerTelemetryRoutes } from './telemetry/http'

const http = httpRouter()

// CORS handling is required for client side frameworks
authComponent.registerRoutes(http, createAuth, { cors: true })

// Native app auth: Google idToken → mint our own JWT + rotating refresh token.
registerAuthNativeRoutes(http)
registerTelemetryRoutes(http)

// Versioned native config surface:
// - `/v1/config` = device/client-version layer (unauthenticated)
// - `/v1/account-config` = account layer (remote session token or local label)
registerConfigRoutes(http)

const liveTokenHandler = httpAction(async (ctx, req) => {
    const authorization = req.headers.get('authorization')
    const secret = authorization?.startsWith('Bearer ')
        ? authorization.slice('Bearer '.length)
        : null
    if (!secret) {
        return jsonResponse({ error: 'unauthenticated' }, { status: 401 })
    }
    const validation = await ctx.runMutation(
        internal.authNative.mutations.validateSessionToken,
        { tokenHash: await hashSessionSecret(secret) },
    )
    if (!validation.ok) {
        return jsonResponse(
            { error: 'invalid_session', reason: validation.reason },
            { status: 401 },
        )
    }
    const result = await ctx.runAction(
        internal.v1.live.actions.requestLiveTokenForHttp,
        {},
    )

    return jsonResponse(result)
})

http.route({
    path: '/v1/live/token',
    method: 'POST',
    handler: liveTokenHandler,
})

// Resend delivery events (delivered / bounced / failed / complained).
// Signature-verified via RESEND_WEBHOOK_SECRET; throws (500) until that env
// var is set and a webhook pointing here exists in the Resend dashboard.
http.route({
    path: '/resend-webhook',
    method: 'POST',
    handler: httpAction(async (ctx, req) =>
        resend.handleResendEventWebhook(ctx, req),
    ),
})

// Resend inbound mail (`email.received`) for support@walletbot.live: archived
// to the `supportEmails` table and redirected to SUPPORT_FORWARD_TO. Separate
// route and separate signing secret (RESEND_INBOUND_WEBHOOK_SECRET) from the
// delivery-event webhook above — see support/http.ts.
registerSupportRoutes(http)

export default http
