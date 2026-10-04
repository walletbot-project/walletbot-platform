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
import type { LiveTokenError } from './live/helpers'
import { registerSupportRoutes } from './support/http'
import { registerTelemetryRoutes } from './telemetry/http'
import { registerUserDeletionRoutes } from './userDeletion/http'
import { registerWhatsappRoutes } from './whatsapp/http'

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

// WhatsApp Cloud API webhook: GET verification handshake + POST events.
// Signature-verified via WHATSAPP_APP_SECRET; fails closed (500) until that env
// var is set, so an unverified payload can never reach the agent.
registerWhatsappRoutes(http)

// Market exchange rates for the agent's getExchangeRate tool (public data).
registerExchangeRateRoutes(http)

// Account deletion (request by email + emailed-link confirmation). Public,
// unauthenticated by design — see userDeletion/http.ts.
registerUserDeletionRoutes(http)

/** HTTP status for each way a mint can be refused. */
const liveRefusalStatus = (error: LiveTokenError): number => {
    switch (error) {
        case 'rate_limited':
            return 429
        case 'local_accounts_disabled':
            return 403
        case 'ai_consent_required':
            return 403
        case 'unidentified_client':
            return 400
    }
}

/**
 * Deliberately callable WITHOUT authentication: the agent must work on native
 * LOCAL accounts, which have no backend user. An unauthenticated caller
 * identifies itself with `deviceId` and gets the tighter limits in
 * `live/rateLimits.ts`; a signed-in caller's identity always wins over any
 * `deviceId` it also sends.
 */
const liveTokenHandler = httpAction(async (ctx, req) => {
    const requestStartedAt = Date.now()
    // The mint options ride in the JSON body. Old builds POST an empty body —
    // they get the base prompt and only the tools their binaries can execute.
    // `createLiveToken` sanitizes/caps the context itself, so the raw JSON is
    // safe to hand over. Read before auth because an anonymous caller's only
    // identity (`deviceId`) is in here.
    let options: {
        platform?: string
        appVersion?: string
        locale?: string
        timezone?: string
        timezoneOffsetMinutes?: number
        context?: unknown
    } = {}
    let localAccountId: string | undefined
    let deviceId: string | undefined
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
            localAccountId =
                typeof record.localAccountId === 'string'
                    ? record.localAccountId
                    : undefined
            deviceId =
                typeof record.deviceId === 'string'
                    ? record.deviceId
                    : undefined
        }
    } catch {
        // Empty or non-JSON body — mint with defaults.
    }

    const authorization = req.headers.get('authorization')
    const secret = authorization?.startsWith('Bearer ')
        ? authorization.slice('Bearer '.length)
        : null
    let userId: string | null = null
    if (secret) {
        const validation = await ctx.runQuery(
            internal.authNative.mutations.validateSessionToken,
            { tokenHash: await hashSessionSecret(secret) },
        )
        // A present-but-invalid token is a broken session, not an anonymous
        // caller: fail it rather than silently downgrading to the device limit
        // and minting under someone else's quota.
        if (!validation.ok) {
            return jsonResponse(
                { error: 'invalid_session', reason: validation.reason },
                { status: 401 },
            )
        }
        userId = validation.userId
    }

    const gate = await ctx.runMutation(
        internal.live.internal.consumeMintLimit,
        { userId: userId ?? undefined, deviceId },
    )
    if (!gate.ok) {
        return jsonResponse(
            { error: gate.error, retryAfter: gate.retryAfter },
            { status: liveRefusalStatus(gate.error) },
        )
    }

    // Register before any new AI usage can emit costs. Missing identities from
    // older builds and failed bookkeeping do not prevent a voice session.
    if (!userId && deviceId && localAccountId) {
        try {
            await ctx.runMutation(internal.appUsers.internal.registerLocal, {
                deviceId,
                localAccountId,
            })
        } catch {
            console.warn('appUsers: registration failed at live-token mint')
        }
    }

    // Flag-gated tools are resolved server-side, never taken from the request
    // body. A null user resolves to each flag's global default, which is the
    // whole flag story for an anonymous caller: no identity, no overrides.
    const flags = await ctx.runQuery(
        internal.featureFlags.internal.resolveFlagsForUserInternal,
        { userId },
    )
    const validatedAt = Date.now()
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
