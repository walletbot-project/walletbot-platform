import { postAuthEndpoint } from '@/lib/auth-endpoint'

/**
 * Requests a password-reset email.
 *
 * Posts to the backend's `/auth/password/forgot` rather than
 * `authClient.requestPasswordReset`, for the same reason sign-up does: the
 * stock route resolves an unknown address successfully without invoking the
 * send hook, so "we sent you a link" was shown for addresses that have no
 * account. The backend endpoint looks the address up first, so `sent` means
 * an email really went out and the screen can say so plainly.
 */

export type PasswordResetOutcome =
    | { status: 'sent' }
    | { status: 'account-not-found' }
    | { status: 'rate-limited' }
    | { status: 'email-send-failed' }
    | { status: 'error'; message: string }

export async function requestPasswordReset(
    email: string,
): Promise<PasswordResetOutcome> {
    // No redirectTo: the backend canonicalizes the link to land on
    // /reset-password.
    const result = await postAuthEndpoint('/auth/password/forgot', { email })

    switch (result.status) {
        case 'ok':
            return { status: 'sent' }
        case 'error':
            return { status: 'error', message: result.message }
        case 'code':
            switch (result.code) {
                case 'account_not_found':
                    return { status: 'account-not-found' }
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
