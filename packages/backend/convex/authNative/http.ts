import type { HttpRouter } from 'convex/server'
import { internal } from '../_generated/api'
import { httpAction } from '../_generated/server'
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
    const user = result.user
    if (typeof user.id !== 'string') {
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
