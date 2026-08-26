import { requireRunMutationCtx } from '@convex-dev/better-auth/utils'
import type { HttpRouter } from 'convex/server'
import { internal } from '../_generated/api'
import { httpAction } from '../_generated/server'
import { authComponent, createAuth } from '../auth'
import {
    outboundLocaleForUser,
    sendAccountDeletionEmail,
} from '../emails/helpers'
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

    // `{ ok: true }` now means one thing only: a deletion email was handed to
    // Resend for this address. Every other outcome gets its own code, so no
    // client can render "check your inbox" for mail that never went out.
    // This deliberately reveals whether an address is registered — the same
    // trade `/auth/email/sign-up` already makes (docs/riesgos.md R-002).
    const { auth } = await authComponent.getAuth(createAuth, ctx)
    const authCtx = await auth.$context
    const found = await authCtx.internalAdapter.findUserByEmail(email)
    if (!found) {
        return jsonError(
            404,
            'account_not_found',
            'No existe una cuenta con ese correo.',
        )
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
    if (!created.ok) {
        return created.reason === 'already_deleted'
            ? jsonError(
                  410,
                  'account_already_deleted',
                  'Esa cuenta ya fue eliminada.',
              )
            : jsonError(
                  429,
                  'rate_limited',
                  'Ya pediste varios enlaces de eliminación. Esperá una hora y probá de nuevo.',
              )
    }

    try {
        const runCtx = requireRunMutationCtx(ctx)
        await sendAccountDeletionEmail(runCtx, {
            to: email,
            name: found.user.name ?? null,
            url: `${siteUrl}/delete-account/confirm?token=${token}`,
            locale: await outboundLocaleForUser(runCtx, {
                userId: found.user.id,
                request: req,
            }),
        })
    } catch (err) {
        // The user exists and the send really failed (Resend config, enqueue,
        // template). Keep the stack: it's the only trail.
        console.error(
            'userDeletion: sendAccountDeletionEmail failed',
            err instanceof Error ? (err.stack ?? err.message) : String(err),
        )
        // Drop the row we just wrote. It counts against the hourly cap, so
        // leaving it would let three transient Resend errors lock the user out
        // of their own deletion link for an hour.
        await ctx.runMutation(internal.userDeletion.internal.deleteRequest, {
            requestId: created.requestId,
        })
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
        // better-auth 1.6 split the old `deleteSessions(userIdOrTokens)`:
        // `deleteSessions` now takes session tokens, `deleteUserSessions`
        // takes the user id.
        await authCtx.internalAdapter.deleteUserSessions(result.userId)
    } catch (err) {
        console.error(
            'userDeletion: deleteUserSessions failed',
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
