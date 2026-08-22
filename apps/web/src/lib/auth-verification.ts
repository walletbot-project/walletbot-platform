import { postAuthEndpoint } from '@/lib/auth-endpoint'

/**
 * Re-sends the verification email for `email`.
 *
 * Posts to the backend's `/auth/email/resend-verification` rather than
 * `authClient.sendVerificationEmail`: better-auth's route resolves an unknown
 * or already-verified address successfully *without* invoking the send hook,
 * so the stock client reported "verification email sent again" for mail that
 * never went out — the trap Google-registered addresses (already verified)
 * fell into every single time. Reporting, and the cooldown, are the caller's:
 * only `sent` warrants one.
 */

export type ResendVerificationOutcome =
    /** The email was really handed to Resend. */
    | { status: 'sent' }
    /** No account for this address at all. */
    | { status: 'account-not-found' }
    /** Already verified — there is nothing to re-send, just sign in. */
    | { status: 'already-verified' }
    /** Too many sends for this address; the cap is per recipient. */
    | { status: 'rate-limited' }
    /** The account resolved but the send failed (Resend config, template). */
    | { status: 'email-send-failed' }
    /** Network failure, or a code this client doesn't know. */
    | { status: 'error'; message: string }

export async function resendVerificationEmail(
    email: string,
): Promise<ResendVerificationOutcome> {
    // No callbackURL: the link's landing page is canonicalized server-side to
    // /verify-email.
    const result = await postAuthEndpoint('/auth/email/resend-verification', {
        email,
    })

    switch (result.status) {
        case 'ok':
            return { status: 'sent' }
        case 'error':
            return { status: 'error', message: result.message }
        case 'code':
            switch (result.code) {
                case 'account_not_found':
                    return { status: 'account-not-found' }
                case 'email_already_verified':
                    return { status: 'already-verified' }
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
