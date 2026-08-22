import { toast } from 'sonner'
import { authClient } from '@/lib/auth-client'
import type { Messages } from '@/lib/i18n'

/**
 * Re-sends the verification email for `email`, reporting through a toast.
 * Shared by the login screen's pending panel and the standalone route.
 */
export function resendVerificationEmail(email: string, t: Messages) {
    // No callbackURL: the link's landing page is canonicalized server-side to
    // /verify-email.
    const promise = authClient
        .sendVerificationEmail({ email })
        .then((result) => {
            if (result.error) {
                throw new Error(
                    result.error.message ?? t.auth.resendVerificationFailed,
                )
            }
        })
    toast.promise(promise, {
        loading: t.auth.resendingVerificationEmail,
        success: t.auth.verificationEmailResent,
        error: t.auth.resendVerificationFailed,
    })
    return promise
}
