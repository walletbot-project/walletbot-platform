/**
 * Shared plumbing for the backend's own auth HTTP endpoints
 * (`packages/backend/convex/authNative/http.ts` and `userDeletion/http.ts`).
 *
 * The web app posts to these instead of using better-auth's stock client
 * routes wherever the stock route cannot tell "we sent an email" apart from
 * "there was nothing to send": under `requireEmailVerification` better-auth
 * answers an unknown or already-registered address with a success that
 * invokes no send hook, so the UI reported mail that never went out. Our
 * endpoints resolve the address first and answer with a `{ code }` naming
 * exactly what happened.
 */

/** The `{ code, message }` shape every one of those endpoints errors with. */
type ErrorBody = { code?: string; message?: string }

export type AuthEndpointResult =
    /** 2xx — the server did the thing (an email really was handed to Resend). */
    | { status: 'ok' }
    /** A `{ code }` the caller knows how to render. */
    | { status: 'code'; code: string; message?: string }
    /** Network failure, non-JSON body, or a code the caller doesn't map. */
    | { status: 'error'; message: string }

export async function postAuthEndpoint(
    path: string,
    body: Record<string, unknown>,
): Promise<AuthEndpointResult> {
    const baseUrl = import.meta.env.VITE_CONVEX_SITE_URL

    let response: Response
    try {
        response = await fetch(`${baseUrl}${path}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        })
    } catch (err) {
        return {
            status: 'error',
            message: err instanceof Error ? err.message : String(err),
        }
    }

    if (response.ok) return { status: 'ok' }

    const parsed = (await response.json().catch(() => null)) as ErrorBody | null
    if (typeof parsed?.code === 'string') {
        return {
            status: 'code',
            code: parsed.code,
            message: parsed.message,
        }
    }
    return {
        status: 'error',
        message: parsed?.message ?? `request failed (${response.status})`,
    }
}
