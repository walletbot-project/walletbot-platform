/**
 * Email sign-up for the web app.
 *
 * Deliberately posts to the backend's own `/auth/email/sign-up` HTTP endpoint
 * (packages/backend/convex/authNative/http.ts) instead of better-auth's stock
 * `authClient.signUp.email`. Under `requireEmailVerification` better-auth
 * answers a duplicate sign-up with a SYNTHETIC user and sends no email — the
 * stock route can't tell that apart from a real new account, so a re-sign-up
 * of an unverified address stranded the user on the verify screen waiting for
 * mail that never went out. The custom endpoint resolves the address first and
 * answers honestly: it re-sends the link for an unverified account, reports a
 * real conflict for an existing one, and surfaces send failures as errors.
 * This keeps web and native on one code path.
 */

type SignUpArgs = {
    name: string
    email: string
    password: string
    termsAcceptedVersion: string
}

export type SignUpOutcome =
    // New account created, or an unverified account had its link re-sent:
    // either way, show the verify-pending panel.
    | { status: 'verify-pending' }
    // A usable account already exists for this email (verified, or social).
    | { status: 'account-exists' }
    // Too many sign-up/re-send attempts for this address.
    | { status: 'rate-limited' }
    // The account resolved fine but the verification email failed to send.
    | { status: 'email-send-failed' }
    // Anything else (validation, network, unexpected server error).
    | { status: 'error'; message: string }

type ErrorBody = { code?: string; message?: string }

export async function signUpWithEmail(
    args: SignUpArgs,
): Promise<SignUpOutcome> {
    const baseUrl = import.meta.env.VITE_CONVEX_SITE_URL

    let response: Response
    try {
        response = await fetch(`${baseUrl}/auth/email/sign-up`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(args),
        })
    } catch (err) {
        return {
            status: 'error',
            message: err instanceof Error ? err.message : String(err),
        }
    }

    // With email verification required the endpoint never mints a session on
    // sign-up; the happy path is a 403 `email_not_verified`. Treat an
    // unexpected 2xx defensively as the same pending state.
    if (response.ok) return { status: 'verify-pending' }

    const body = (await response.json().catch(() => null)) as ErrorBody | null

    switch (body?.code) {
        case 'email_not_verified':
            return { status: 'verify-pending' }
        case 'account_exists':
            return { status: 'account-exists' }
        case 'rate_limited':
            return { status: 'rate-limited' }
        case 'email_send_failed':
            return { status: 'email-send-failed' }
        default:
            return {
                status: 'error',
                message: body?.message ?? `sign up failed (${response.status})`,
            }
    }
}
