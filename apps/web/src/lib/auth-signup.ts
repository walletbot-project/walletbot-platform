import { postAuthEndpoint } from '@/lib/auth-endpoint'

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
    /**
     * Legal-documents version shown next to the acceptance checkbox. The
     * endpoint validates it and hands it to better-auth as an
     * `additionalFields` entry, so the acceptance is recorded against the real
     * user insert by the user-create hook (see `convex/auth.ts`). Web sign-up
     * moved onto this endpoint, so dropping the field here would silently lose
     * the acceptance and leave the post-login gate re-prompting every new
     * account.
     */
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

export async function signUpWithEmail(
    args: SignUpArgs,
): Promise<SignUpOutcome> {
    const result = await postAuthEndpoint('/auth/email/sign-up', args)

    switch (result.status) {
        // With email verification required the endpoint never mints a session
        // on sign-up; the happy path is a 403 `email_not_verified`. Treat an
        // unexpected 2xx defensively as the same pending state.
        case 'ok':
            return { status: 'verify-pending' }
        case 'error':
            return { status: 'error', message: result.message }
        case 'code':
            switch (result.code) {
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
                        message: result.message ?? result.code,
                    }
            }
    }
}
