import { postAuthEndpoint } from '@/lib/auth-endpoint'

/**
 * Requests the account-deletion confirmation email.
 *
 * `/v1/account-deletion/request` used to answer every outcome — unknown
 * address, hourly cap reached, account already deleted, Resend failure — with
 * the same `{ ok: true }`, so the page said "we sent a link to <address>" for
 * mail it had no idea about. It now names each case, and `sent` is the only
 * one that means an email exists.
 */

export type AccountDeletionRequestOutcome =
    | { status: 'sent' }
    | { status: 'account-not-found' }
    | { status: 'already-deleted' }
    | { status: 'rate-limited' }
    | { status: 'email-send-failed' }
    | { status: 'error'; message: string }

export async function requestAccountDeletion(
    email: string,
): Promise<AccountDeletionRequestOutcome> {
    const result = await postAuthEndpoint('/v1/account-deletion/request', {
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
                case 'account_already_deleted':
                    return { status: 'already-deleted' }
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
