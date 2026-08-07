import { APIError } from 'better-auth/api'
import type { HttpRouter } from 'convex/server'
import { internal } from '../_generated/api'
import { type ActionCtx, httpAction } from '../_generated/server'
import { authComponent, createAuth } from '../auth'
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

const googleSignIn = httpAction(async (ctx, req) => {
    const body = await parseJsonBody<GoogleSignInBody>(req)
    if (
        !body ||
        typeof body.idToken !== 'string' ||
        body.idToken.length === 0
    ) {
        return jsonError(400, 'bad_request', 'missing idToken')
    }

    const { auth, headers } = await authComponent.getAuth(createAuth, ctx)

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
            headers,
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

    if (isNewSocialUserResult(result)) {
        await ctx.runMutation(
            internal.telemetry.mutations.recordUserAccountCreated,
            {
                userId: result.user.id,
                authMethod: 'google',
            },
        )
    }

    return issueNativeSession(ctx, req, result.user)
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

const emailSignIn = httpAction(async (ctx, req) => {
    const parsed = getEmailAndPassword(
        await parseJsonBody<EmailSignInBody>(req),
    )
    if (parsed instanceof Response) return parsed

    const { auth, headers } = await authComponent.getAuth(createAuth, ctx)

    try {
        const result = await auth.api.signInEmail({
            body: {
                email: parsed.email,
                password: parsed.password,
            },
            headers,
        })
        return issueNativeSession(ctx, req, result.user)
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
})

const emailSignUp = httpAction(async (ctx, req) => {
    const body = await parseJsonBody<EmailSignUpBody>(req)
    const parsed = getEmailAndPassword(body)
    if (parsed instanceof Response) return parsed

    const name =
        typeof body?.name === 'string' && body.name.trim().length > 0
            ? body.name.trim()
            : parsed.email

    const { auth, headers } = await authComponent.getAuth(createAuth, ctx)

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
        if (!result.token) {
            return jsonError(
                403,
                'email_not_verified',
                'Revisá tu correo: te enviamos un enlace para verificar tu cuenta.',
            )
        }
        // Deliberately below the gate: recording above it would count
        // duplicate-email attempts under better-auth's synthetic fake id.
        await ctx.runMutation(
            internal.telemetry.mutations.recordUserAccountCreated,
            {
                userId: result.user.id,
                authMethod: 'email_password',
            },
        )
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

const forgotPasswordHandler = httpAction(async (ctx, req) => {
    const email = getEmail(await parseJsonBody<EmailOnlyBody>(req))
    if (email instanceof Response) return email

    const { auth, headers } = await authComponent.getAuth(createAuth, ctx)
    try {
        await auth.api.requestPasswordReset({ body: { email }, headers })
    } catch (err) {
        return emailSendFailedResponse('requestPasswordReset', err)
    }
    return jsonResponse({ ok: true })
})

const resendVerificationHandler = httpAction(async (ctx, req) => {
    const email = getEmail(await parseJsonBody<EmailOnlyBody>(req))
    if (email instanceof Response) return email

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

const refreshHandler = httpAction(async (ctx, req) => {
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

const signOutHandler = httpAction(async (ctx, req) => {
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
