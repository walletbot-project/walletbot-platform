import { requireRunMutationCtx } from '@convex-dev/better-auth/utils'
import type { HttpRouter } from 'convex/server'
import { internal } from '../_generated/api'
import { httpAction } from '../_generated/server'
import { authComponent, createAuth } from '../auth'
import { sendAccountDeletionEmail } from '../emails/helpers'
import { jsonResponse, preflightResponse } from '../httpHelpers'
import {
    DELETION_TOKEN_TTL_MS,
    generateDeletionToken,
    hashDeletionToken,
} from './helpers'

// Account deletion is a custom token flow instead of better-auth's built-in
// `user.deleteUser`: that one requires an active session even when confirming
// by token, and the product requires requesting deletion while logged out
// (Play's data-deletion policy: web-accessible deletion URL). Possession of
// the emailed link is the authorization, same trust model as password reset.
//
// If 2FA is added later, the confirm step must additionally challenge the
// second factor before consuming the token.

const jsonError = (status: number, code: string, message: string): Response =>
    jsonResponse({ code, message }, { status })

const parseJsonBody = async <T>(req: Request): Promise<T | null> => {
    try {
        return (await req.json()) as T
    } catch {
        return null
    }
}

type EmailBody = { email?: string }
type TokenBody = { token?: string }

const requestHandler = httpAction(async (ctx, req) => {
    const body = await parseJsonBody<EmailBody>(req)
    if (
        !body ||
        typeof body.email !== 'string' ||
        body.email.trim().length === 0
    ) {
        return jsonError(400, 'bad_request', 'missing email')
    }
    const email = body.email.trim().toLowerCase()

    const siteUrl = process.env.SITE_URL
    if (!siteUrl) {
        return jsonError(500, 'misconfigured', 'SITE_URL not set')
    }

    // Anti-enumeration: every outcome below except a real email-send failure
    // answers with the same generic success.
    const { auth } = await authComponent.getAuth(createAuth, ctx)
    const authCtx = await auth.$context
    const found = await authCtx.internalAdapter.findUserByEmail(email)
    if (!found) {
        return jsonResponse({ ok: true })
    }

    const token = generateDeletionToken()
    const created = await ctx.runMutation(
        internal.userDeletion.internal.createRequest,
        {
            userId: found.user.id,
            email,
            tokenHash: await hashDeletionToken(token),
            expiresAt: Date.now() + DELETION_TOKEN_TTL_MS,
        },
    )
    if (!created) {
        // Throttled or already deleted — still generic.
        return jsonResponse({ ok: true })
    }

    try {
        await sendAccountDeletionEmail(requireRunMutationCtx(ctx), {
            to: email,
            name: found.user.name ?? null,
            url: `${siteUrl}/delete-account/confirm?token=${token}`,
        })
    } catch (err) {
        // The user exists and the send really failed (Resend config,
        // enqueue, template) — same reasoning as authNative's
        // emailSendFailedResponse. Keep the stack: it's the only trail.
        console.error(
            'userDeletion: sendAccountDeletionEmail failed',
            err instanceof Error ? (err.stack ?? err.message) : String(err),
        )
        return jsonError(
            500,
            'email_send_failed',
            'No pudimos enviar el correo. Probá de nuevo en unos minutos.',
        )
    }

    return jsonResponse({ ok: true })
})

const confirmHandler = httpAction(async (ctx, req) => {
    const body = await parseJsonBody<TokenBody>(req)
    if (
        !body ||
        typeof body.token !== 'string' ||
        body.token.trim().length === 0
    ) {
        return jsonError(400, 'bad_request', 'missing token')
    }

    const result = await ctx.runMutation(
        internal.userDeletion.internal.consumeToken,
        { tokenHash: await hashDeletionToken(body.token.trim()) },
    )
    if (!result.ok) {
        return jsonResponse(
            { ok: false, error: 'invalid_token' },
            { status: 400 },
        )
    }

    // Immediate web lockout, best effort — the purge's finalize step deletes
    // the sessions again, so a failure here only widens the window.
    try {
        const { auth } = await authComponent.getAuth(createAuth, ctx)
        const authCtx = await auth.$context
        await authCtx.internalAdapter.deleteSessions(result.userId)
    } catch (err) {
        console.error(
            'userDeletion: deleteSessions failed',
            err instanceof Error ? (err.stack ?? err.message) : String(err),
        )
    }

    return jsonResponse({ ok: true })
})

export const registerUserDeletionRoutes = (http: HttpRouter): void => {
    http.route({
        path: '/v1/account-deletion/request',
        method: 'POST',
        handler: requestHandler,
    })
    http.route({
        path: '/v1/account-deletion/request',
        method: 'OPTIONS',
        handler: httpAction(async () => preflightResponse()),
    })
    http.route({
        path: '/v1/account-deletion/confirm',
        method: 'POST',
        handler: confirmHandler,
    })
    http.route({
        path: '/v1/account-deletion/confirm',
        method: 'OPTIONS',
        handler: httpAction(async () => preflightResponse()),
    })
}
