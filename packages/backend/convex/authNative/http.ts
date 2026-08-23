import { APIError } from 'better-auth/api'
import type { HttpRouter } from 'convex/server'
import { internal } from '../_generated/api'
import { type ActionCtx, httpAction } from '../_generated/server'
import { authComponent, createAuth } from '../auth'
import { authRateLimiter } from './rateLimits'
import {
    generateSessionSecret,
    hashSessionSecret,
    mintAccessToken,
} from './utils'

const jsonResponse = (body: unknown, init?: ResponseInit): Response => {
    const headers = new Headers(init?.headers)
    if (!headers.has('Content-Type')) {
        headers.set('Content-Type', 'application/json')
    }
    return new Response(JSON.stringify(body), { ...init, headers })
}

const jsonError = (status: number, code: string, message: string): Response =>
    jsonResponse({ code, message }, { status })

// Browser CORS for the /auth/* surface. Native mobile clients never send an
// Origin header and are unaffected. Flutter web dev servers pick a random
// port, so any localhost origin is allowed; when a web build gets a real
// domain it goes in ALLOWED_WEB_ORIGINS. These endpoints authenticate via
// explicit tokens in the body or Authorization header (never cookies), so
// reflecting the origin adds no CSRF surface.
const ALLOWED_WEB_ORIGINS: readonly string[] = []

const LOCALHOST_ORIGIN_PATTERN = /^https?:\/\/localhost(:\d+)?$/

const allowedOrigin = (req: Request): string | null => {
    const origin = req.headers.get('origin')
    if (!origin) return null
    return LOCALHOST_ORIGIN_PATTERN.test(origin) ||
        ALLOWED_WEB_ORIGINS.includes(origin)
        ? origin
        : null
}

const withCorsHeaders = (req: Request, res: Response): Response => {
    const origin = allowedOrigin(req)
    if (!origin) return res
    const headers = new Headers(res.headers)
    headers.set('Access-Control-Allow-Origin', origin)
    headers.set('Vary', 'Origin')
    return new Response(res.body, {
        status: res.status,
        statusText: res.statusText,
        headers,
    })
}

// httpAction wrapper for browser-callable routes: reflects the allowed
// origin onto whatever response the handler returns.
const corsHttpAction = (
    fn: (ctx: ActionCtx, req: Request) => Promise<Response>,
) => httpAction(async (ctx, req) => withCorsHeaders(req, await fn(ctx, req)))

const parseJsonBody = async <T>(req: Request): Promise<T | null> => {
    try {
        return (await req.json()) as T
    } catch {
        return null
    }
}

type GoogleSignInBody = {
    idToken?: string
    accessToken?: string
    nonce?: string
}

type EmailSignInBody = {
    email?: string
    password?: string
}

type EmailSignUpBody = EmailSignInBody & {
    name?: string
}

type NativeAuthUser = {
    id: string
    email?: string | null
    name?: string | null
    image?: string | null
}

const isNewSocialUserResult = (value: unknown): boolean => {
    if (typeof value !== 'object' || value === null) return false
    const record = value as Record<string, unknown>
    return record.isNewUser === true || record.newUser === true
}

const issueNativeSession = async (
    ctx: ActionCtx,
    req: Request,
    user: NativeAuthUser,
): Promise<Response> => {
    if (typeof user.id !== 'string' || user.id.length === 0) {
        return jsonError(
            500,
            'sign_in_failed',
            'sign-in user record missing id',
        )
    }

    const sessionSecret = generateSessionSecret()
    const tokenHash = await hashSessionSecret(sessionSecret)

    await ctx.runMutation(internal.authNative.mutations.insertSessionToken, {
        userId: user.id,
        tokenHash,
        createdAt: Date.now(),
        userAgent: req.headers.get('user-agent') ?? undefined,
    })

    const access = await mintAccessToken(user.id)

    return jsonResponse({
        accessToken: access.token,
        accessTokenExpiresAt: access.expiresAt,
        refreshToken: sessionSecret,
        user: {
            id: user.id,
            email: user.email ?? null,
            name: user.name ?? null,
            image: user.image ?? null,
        },
    })
}

const recordNativeSignInTelemetry = async (
    ctx: ActionCtx,
    args: { userId: string; authMethod: 'email_password' | 'google' },
): Promise<void> => {
    try {
        await ctx.runMutation(
            internal.telemetry.mutations.recordUserAccountSignedIn,
            {
                userId: args.userId,
                authMethod: args.authMethod,
                clientPlatform: 'native',
            },
        )
    } catch (error) {
        console.warn('native sign-in telemetry failed', {
            userId: args.userId,
            authMethod: args.authMethod,
            error: error instanceof Error ? error.message : String(error),
        })
    }
}

const googleSignIn = corsHttpAction(async (ctx, req) => {
    const body = await parseJsonBody<GoogleSignInBody>(req)
    if (
        !body ||
        typeof body.idToken !== 'string' ||
        body.idToken.length === 0
    ) {
        return jsonError(400, 'bad_request', 'missing idToken')
    }

    const { auth, headers } = await authComponent.getAuth(createAuth, ctx)
    const authHeaders = new Headers(headers)
    authHeaders.set('x-walletbot-client-platform', 'native')

    let result: Awaited<ReturnType<typeof auth.api.signInSocial>>
    try {
        result = await auth.api.signInSocial({
            body: {
                provider: 'google',
                idToken: {
                    token: body.idToken,
                    ...(body.accessToken
                        ? { accessToken: body.accessToken }
                        : {}),
                    ...(body.nonce ? { nonce: body.nonce } : {}),
                },
            },
            headers: authHeaders,
        })
    } catch (err) {
        const message = err instanceof Error ? err.message : String(err)
        return jsonError(401, 'sign_in_failed', message)
    }

    // Narrow the union returned by signInSocial — the idToken path returns
    // a `user` object; the redirect path returns `{ url, redirect: true }`.
    if (!('user' in result) || !result.user) {
        return jsonError(500, 'sign_in_failed', 'sign-in did not return a user')
    }

    const response = await issueNativeSession(ctx, req, result.user)

    if (isNewSocialUserResult(result)) {
        try {
            await ctx.runMutation(
                internal.telemetry.mutations.recordUserAccountCreated,
                {
                    userId: result.user.id,
                    authMethod: 'google',
                },
            )
        } catch (error) {
            console.warn('native account-created telemetry failed', {
                userId: result.user.id,
                authMethod: 'google',
                error: error instanceof Error ? error.message : String(error),
            })
        }
    }
    await recordNativeSignInTelemetry(ctx, {
        userId: result.user.id,
        authMethod: 'google',
    })

    return response
})

const getEmailAndPassword = (
    body: EmailSignInBody | null,
): { email: string; password: string } | Response => {
    if (
        !body ||
        typeof body.email !== 'string' ||
        body.email.trim().length === 0 ||
        typeof body.password !== 'string' ||
        body.password.length === 0
    ) {
        return jsonError(400, 'bad_request', 'missing email or password')
    }

    return { email: body.email.trim().toLowerCase(), password: body.password }
}

const emailSignIn = corsHttpAction(async (ctx, req) => {
    const parsed = getEmailAndPassword(
        await parseJsonBody<EmailSignInBody>(req),
    )
    if (parsed instanceof Response) return parsed

    const { auth, headers } = await authComponent.getAuth(createAuth, ctx)
    const authHeaders = new Headers(headers)
    authHeaders.set('x-walletbot-client-platform', 'native')

    let result: Awaited<ReturnType<typeof auth.api.signInEmail>>
    try {
        result = await auth.api.signInEmail({
            body: {
                email: parsed.email,
                password: parsed.password,
            },
            headers: authHeaders,
        })
    } catch (err) {
        // Better-auth already re-sent the verification email on this attempt
        // (sendOnSignIn), so the client only needs to show the pending state.
        if (
            err instanceof APIError &&
            err.body?.code === 'EMAIL_NOT_VERIFIED'
        ) {
            return jsonError(
                403,
                'email_not_verified',
                'Tenés que verificar tu correo. Te enviamos un nuevo enlace de verificación.',
            )
        }
        const message = err instanceof Error ? err.message : String(err)
        return jsonError(401, 'sign_in_failed', message)
    }

    const response = await issueNativeSession(ctx, req, result.user)
    await recordNativeSignInTelemetry(ctx, {
        userId: result.user.id,
        authMethod: 'email_password',
    })
    return response
})

const emailSignUp = corsHttpAction(async (ctx, req) => {
    const body = await parseJsonBody<EmailSignUpBody>(req)
    const parsed = getEmailAndPassword(body)
    if (parsed instanceof Response) return parsed

    const name =
        typeof body?.name === 'string' && body.name.trim().length > 0
            ? body.name.trim()
            : parsed.email

    const { auth, headers } = await authComponent.getAuth(createAuth, ctx)

    // better-auth answers a duplicate sign-up with a SYNTHETIC user and
    // `token: null` — deliberately indistinguishable from a real pending
    // verification, and it sends no email. Reporting that as "check your
    // inbox" stranded users on a verify screen waiting for mail that was
    // never sent (typically Google-registered accounts). So resolve the
    // address first and answer honestly. This trades sign-up enumeration
    // resistance for a usable recovery path; forgot/resend stay opaque
    // (see docs/riesgos.md R-002).
    const { internalAdapter } = await auth.$context
    const existing = await internalAdapter.findUserByEmail(parsed.email, {
        includeAccounts: true,
    })

    if (existing) {
        // `credential` is better-auth's providerId for email+password.
        const hasPassword = existing.accounts.some(
            (account) => account.providerId === 'credential',
        )
        // An unverified password account re-running sign-up is not a
        // conflict, it's someone who lost the first link: re-send it and
        // keep the verify-pending flow. Rate limited per address, like the
        // dedicated resend route.
        if (hasPassword && !existing.user.emailVerified) {
            const { ok } = await authRateLimiter.limit(
                ctx,
                'verificationEmail',
                {
                    key: parsed.email,
                },
            )
            if (!ok) return rateLimitedResponse()
            try {
                await auth.api.sendVerificationEmail({
                    body: { email: parsed.email },
                    headers,
                })
            } catch (err) {
                return emailSendFailedResponse('sendVerificationEmail', err)
            }
            return jsonError(
                403,
                'email_not_verified',
                'Revisá tu correo: te enviamos un enlace para verificar tu cuenta.',
            )
        }

        // Deliberately does NOT say which provider the account uses: an
        // account can hold both a password and a social login, and naming
        // one would leak more than "this address is taken". The client
        // tells the user to sign in with either.
        return jsonError(
            409,
            'account_exists',
            'Ya existe una cuenta con ese correo.',
        )
    }

    try {
        const result = await auth.api.signUpEmail({
            body: {
                name,
                email: parsed.email,
                password: parsed.password,
            },
            headers,
        })
        // With requireEmailVerification there is no session yet (`token` is
        // null) and duplicate emails return a SYNTHETIC user with a fake id —
        // gate on the token, never mint a session from `result.user` alone.
        // Account-creation telemetry can't live here for the same reason: this
        // branch is taken for BOTH cases. It hangs off the real row insert in
        // `databaseHooks.user.create.after` (see `auth.ts`) instead.
        if (!result.token) {
            return jsonError(
                403,
                'email_not_verified',
                'Revisá tu correo: te enviamos un enlace para verificar tu cuenta.',
            )
        }
        return issueNativeSession(ctx, req, result.user)
    } catch (err) {
        const message = err instanceof Error ? err.message : String(err)
        return jsonError(400, 'sign_up_failed', message)
    }
})

type EmailOnlyBody = {
    email?: string
}

const getEmail = (body: EmailOnlyBody | null): string | Response => {
    if (
        !body ||
        typeof body.email !== 'string' ||
        body.email.trim().length === 0
    ) {
        return jsonError(400, 'bad_request', 'missing email')
    }
    return body.email.trim().toLowerCase()
}

// Enumeration safety comes from better-auth itself: an unknown (or already
// verified) email resolves successfully WITHOUT invoking the send hook, so a
// throw here never means "user not found" — it is a real failure (Resend
// config, enqueue, template). Masking those as success left users waiting
// for emails that never went out; surface them as 500 instead. The client
// still can't learn whether an email exists.
const emailSendFailedResponse = (op: string, err: unknown): Response => {
    // This log is the only server-side forensic trail — keep the stack.
    console.error(
        `authNative: ${op} failed`,
        err instanceof Error ? (err.stack ?? err.message) : String(err),
    )
    return jsonError(
        500,
        'email_send_failed',
        'No pudimos enviar el correo. Probá de nuevo en unos minutos.',
    )
}

// Keyed by address, so no inbox can be mail-bombed through these routes. The
// counter advances before better-auth is consulted and regardless of whether
// the address is registered, so a 429 reveals nothing an attacker could use to
// enumerate accounts. Note this bounds sends *per recipient*, not per caller:
// spreading attempts across many addresses is still possible, which would need
// a client-IP dimension we can't trust from a header here.
const rateLimitedResponse = (): Response =>
    jsonError(
        429,
        'rate_limited',
        'Demasiados intentos. Esperá un minuto y probá de nuevo.',
    )

const forgotPasswordHandler = corsHttpAction(async (ctx, req) => {
    const email = getEmail(await parseJsonBody<EmailOnlyBody>(req))
    if (email instanceof Response) return email

    const { ok } = await authRateLimiter.limit(ctx, 'passwordResetEmail', {
        key: email,
    })
    if (!ok) return rateLimitedResponse()

    const { auth, headers } = await authComponent.getAuth(createAuth, ctx)
    try {
        await auth.api.requestPasswordReset({ body: { email }, headers })
    } catch (err) {
        return emailSendFailedResponse('requestPasswordReset', err)
    }
    return jsonResponse({ ok: true })
})

const resendVerificationHandler = corsHttpAction(async (ctx, req) => {
    const email = getEmail(await parseJsonBody<EmailOnlyBody>(req))
    if (email instanceof Response) return email

    const { ok } = await authRateLimiter.limit(ctx, 'verificationEmail', {
        key: email,
    })
    if (!ok) return rateLimitedResponse()

    const { auth, headers } = await authComponent.getAuth(createAuth, ctx)
    try {
        await auth.api.sendVerificationEmail({ body: { email }, headers })
    } catch (err) {
        return emailSendFailedResponse('sendVerificationEmail', err)
    }
    return jsonResponse({ ok: true })
})

type RefreshBody = {
    refreshToken?: string
}

const refreshHandler = corsHttpAction(async (ctx, req) => {
    const body = await parseJsonBody<RefreshBody>(req)
    if (
        !body ||
        typeof body.refreshToken !== 'string' ||
        body.refreshToken.length === 0
    ) {
        return jsonError(400, 'bad_request', 'missing refreshToken')
    }

    const tokenHash = await hashSessionSecret(body.refreshToken)
    const validation = await ctx.runMutation(
        internal.authNative.mutations.validateSessionToken,
        { tokenHash },
    )

    if (!validation.ok) {
        return jsonError(401, 'invalid_refresh_token', validation.reason)
    }

    const access = await mintAccessToken(validation.userId)

    return jsonResponse({
        accessToken: access.token,
        accessTokenExpiresAt: access.expiresAt,
    })
})

type SignOutBody = {
    refreshToken?: string
}

const signOutHandler = corsHttpAction(async (ctx, req) => {
    const body = await parseJsonBody<SignOutBody>(req)
    if (
        body &&
        typeof body.refreshToken === 'string' &&
        body.refreshToken.length > 0
    ) {
        const hash = await hashSessionSecret(body.refreshToken)
        await ctx.runMutation(
            internal.authNative.mutations.revokeSessionTokenByHash,
            { tokenHash: hash },
        )
    }
    return jsonResponse({ ok: true })
})

const oidcDiscoveryHandler = httpAction(async () => {
    const siteUrl = process.env.CONVEX_SITE_URL
    if (!siteUrl) {
        return jsonError(500, 'misconfigured', 'CONVEX_SITE_URL not set')
    }
    const issuer = `${siteUrl}/native-auth`
    return jsonResponse({
        issuer,
        jwks_uri: `${issuer}/.well-known/jwks.json`,
        id_token_signing_alg_values_supported: ['RS256'],
        response_types_supported: ['id_token'],
        subject_types_supported: ['public'],
    })
})

const jwksHandler = httpAction(async () => {
    const jwks = process.env.JWKS
    if (!jwks) {
        return jsonError(500, 'misconfigured', 'JWKS not set')
    }
    return new Response(jwks, {
        headers: { 'Content-Type': 'application/json' },
    })
})

const preflightHandler = httpAction(async (_ctx, req) => {
    const origin = allowedOrigin(req)
    if (!origin) return new Response(null, { status: 204 })
    return new Response(null, {
        status: 204,
        headers: {
            'Access-Control-Allow-Origin': origin,
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '86400',
            Vary: 'Origin',
        },
    })
})

export const registerAuthNativeRoutes = (http: HttpRouter): void => {
    http.route({ path: '/auth/google', method: 'POST', handler: googleSignIn })
    http.route({
        path: '/auth/email/sign-in',
        method: 'POST',
        handler: emailSignIn,
    })
    http.route({
        path: '/auth/email/sign-up',
        method: 'POST',
        handler: emailSignUp,
    })
    http.route({
        path: '/auth/password/forgot',
        method: 'POST',
        handler: forgotPasswordHandler,
    })
    http.route({
        path: '/auth/email/resend-verification',
        method: 'POST',
        handler: resendVerificationHandler,
    })
    http.route({
        path: '/auth/refresh',
        method: 'POST',
        handler: refreshHandler,
    })
    http.route({
        path: '/auth/signout',
        method: 'POST',
        handler: signOutHandler,
    })

    // Browser preflight for the whole /auth/ namespace (Flutter web). Native
    // mobile clients never send OPTIONS; without this the preflight 404s with
    // no CORS headers and the browser blocks the POST.
    http.route({
        pathPrefix: '/auth/',
        method: 'OPTIONS',
        handler: preflightHandler,
    })
    http.route({
        path: '/native-auth/.well-known/jwks.json',
        method: 'GET',
        handler: jwksHandler,
    })
    http.route({
        path: '/native-auth/.well-known/openid-configuration',
        method: 'GET',
        handler: oidcDiscoveryHandler,
    })
}
