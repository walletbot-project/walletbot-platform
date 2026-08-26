import { httpRouter } from 'convex/server'
import { internal } from './_generated/api'
import { httpAction } from './_generated/server'
import { authComponent, createAuth } from './auth'
import { registerAuthNativeRoutes } from './authNative/http'
import { hashSessionSecret } from './authNative/utils'
import { registerConfigRoutes } from './config/http'
import { resend } from './emails/helpers'
import { registerExchangeRateRoutes } from './exchangeRates/http'
import { jsonResponse } from './httpHelpers'
import { createLiveToken } from './live/createToken'
import { registerSupportRoutes } from './support/http'
import { registerTelemetryRoutes } from './telemetry/http'
import { registerUserDeletionRoutes } from './userDeletion/http'

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

// Market exchange rates for the agent's getExchangeRate tool (public data).
registerExchangeRateRoutes(http)

// Account deletion (request by email + emailed-link confirmation). Public,
// unauthenticated by design — see userDeletion/http.ts.
registerUserDeletionRoutes(http)

const liveTokenHandler = httpAction(async (ctx, req) => {
    const requestStartedAt = Date.now()
    const authorization = req.headers.get('authorization')
    const secret = authorization?.startsWith('Bearer ')
        ? authorization.slice('Bearer '.length)
        : null
    if (!secret) {
        return jsonResponse({ error: 'unauthenticated' }, { status: 401 })
    }
    const validation = await ctx.runQuery(
        internal.authNative.mutations.validateSessionToken,
        { tokenHash: await hashSessionSecret(secret) },
    )
    if (!validation.ok) {
        return jsonResponse(
            { error: 'invalid_session', reason: validation.reason },
            { status: 401 },
        )
    }
    // Flag-gated tools are resolved server-side from the validated session,
    // never taken from the request body.
    const flags = await ctx.runQuery(
        internal.featureFlags.internal.resolveFlagsForUserInternal,
        { userId: validation.userId },
    )
    const validatedAt = Date.now()
    // The mint options ride in the JSON body. Old builds POST an empty body —
    // they get the base prompt and only the tools their binaries can execute.
    // `createLiveToken` sanitizes/caps the context itself, so the raw JSON is
    // safe to hand over.
    let options: {
        platform?: string
        appVersion?: string
        locale?: string
        timezone?: string
        timezoneOffsetMinutes?: number
        context?: unknown
    } = {}
    try {
        const body: unknown = await req.json()
        if (typeof body === 'object' && body !== null && !Array.isArray(body)) {
            const record = body as Record<string, unknown>
            options = {
                platform:
                    typeof record.platform === 'string'
                        ? record.platform
                        : undefined,
                appVersion:
                    typeof record.appVersion === 'string'
                        ? record.appVersion
                        : undefined,
                locale:
                    typeof record.locale === 'string'
                        ? record.locale
                        : undefined,
                timezone:
                    typeof record.timezone === 'string'
                        ? record.timezone
                        : undefined,
                timezoneOffsetMinutes:
                    typeof record.timezoneOffsetMinutes === 'number'
                        ? record.timezoneOffsetMinutes
                        : undefined,
                context: record.context,
            }
        }
    } catch {
        // Empty or non-JSON body — mint with defaults.
    }
    // Direct call: createLiveToken runs in the default runtime (no Node
    // APIs), so no cross-runtime action hop is needed.
    const result = await createLiveToken({ ...options, flags })

    return jsonResponse({
        ...result,
        timings: {
            ...result.timings,
            authMs: validatedAt - requestStartedAt,
            httpTotalMs: Date.now() - requestStartedAt,
        },
    })
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
