import type { HttpRouter } from 'convex/server'
import { internal } from '../_generated/api'
import { type ActionCtx, httpAction } from '../_generated/server'
import { hashSessionSecret } from '../authNative/utils'
import { jsonResponse, preflightResponse } from '../httpHelpers'
import { resolveAccountConfig, resolveConfigVerdict } from './helpers'

type AccountConfigBody = {
    platform?: unknown
    appVersion?: unknown
    deviceId?: unknown
    locale?: unknown
    account?: unknown
}

type AccountConfigAccount =
    | { type: 'remote'; userId: string }
    | { type: 'local'; name: string | null; accountId: string | null }
    | null

const parseJsonBody = async <T>(req: Request): Promise<T | null> => {
    try {
        return (await req.json()) as T
    } catch {
        return null
    }
}

const asString = (value: unknown, fallback: string): string =>
    typeof value === 'string' && value.length > 0 ? value : fallback

// GET /v1/config?platform=ios&appVersion=1.2.0&deviceId=<id>&locale=es-AR
//
// Unauthenticated client-version gate (L1). Returns a `ConfigVerdict`. Clients
// must treat a network/parse failure as "supported" and fall back to their
// bundled + last-good cached config (CLAUDE.md: native config fails open).
const getConfig = httpAction(async (_ctx, req) => {
    const url = new URL(req.url)
    const platform = url.searchParams.get('platform') ?? 'unknown'
    const appVersion = url.searchParams.get('appVersion') ?? '0.0.0'
    const deviceId = url.searchParams.get('deviceId') ?? 'unknown'
    const locale =
        url.searchParams.get('locale') ??
        req.headers.get('accept-language') ??
        'en'

    const verdict = resolveConfigVerdict({
        platform,
        appVersion,
        deviceId,
        locale,
    })
    return jsonResponse(verdict)
})

const accountFromBody = async (
    ctx: ActionCtx,
    rawAccount: unknown,
): Promise<AccountConfigAccount> => {
    if (typeof rawAccount !== 'object' || rawAccount === null) return null
    const account = rawAccount as Record<string, unknown>
    if (account.type === 'local') {
        return {
            type: 'local',
            accountId: typeof account.id === 'string' ? account.id : null,
            name: typeof account.name === 'string' ? account.name : null,
        }
    }
    if (account.type !== 'remote' || typeof account.token !== 'string') {
        return null
    }

    const tokenHash = await hashSessionSecret(account.token)
    const validation = await ctx.runMutation(
        internal.authNative.mutations.validateSessionToken,
        { tokenHash },
    )
    if (!validation.ok) return null
    return { type: 'remote', userId: validation.userId }
}

const postAccountConfig = httpAction(async (ctx, req) => {
    const body = await parseJsonBody<AccountConfigBody>(req)
    const platform = asString(body?.platform, 'unknown')
    const appVersion = asString(body?.appVersion, '0.0.0')
    const deviceId = asString(body?.deviceId, 'unknown')
    const locale = asString(
        body?.locale,
        req.headers.get('accept-language') ?? 'en',
    )
    const account = await accountFromBody(ctx, body?.account)

    const verdict = resolveAccountConfig({
        platform,
        appVersion,
        deviceId,
        locale,
        account,
    })
    return jsonResponse(verdict)
})

export const registerConfigRoutes = (http: HttpRouter): void => {
    http.route({ path: '/v1/config', method: 'GET', handler: getConfig })
    http.route({
        path: '/v1/config',
        method: 'OPTIONS',
        handler: httpAction(async () => preflightResponse()),
    })
    http.route({
        path: '/v1/account-config',
        method: 'POST',
        handler: postAccountConfig,
    })
    http.route({
        path: '/v1/account-config',
        method: 'OPTIONS',
        handler: httpAction(async () => preflightResponse()),
    })
}
