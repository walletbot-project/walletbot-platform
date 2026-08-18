import { Button } from 'actify'
import { type FormEvent, useState } from 'react'
import { toast } from 'sonner'
import {
    AuthMessagePanel,
    AuthPanel,
    AuthPanelTitle,
    AuthPrimaryButton,
    AuthTextField,
} from '@/components/auth/auth-scaffold'
import { authClient } from '@/lib/auth-client'
import { useT } from '@/lib/i18n'

/**
 * The reset-password request, porting the native `_ForgotPasswordPanel`: an
 * email form that flips to a "check your inbox" state once the request went
 * through. Rendered inline by the login screen and by the `/forgot-password`
 * route, which exists for the links that point straight at it.
 */
export function ForgotPasswordPanel({ onBack }: { onBack: () => void }) {
    const t = useT()
    const [submitting, setSubmitting] = useState(false)
    const [sentTo, setSentTo] = useState<string | null>(null)

    const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault()
        setSubmitting(true)

        const email = String(
            new FormData(event.currentTarget).get('email') ?? '',
        )
            .trim()
            .toLowerCase()

        try {
            // No redirectTo: the backend canonicalizes the link to land on
            // /reset-password. The endpoint never discloses whether the email
            // exists, so any non-error response flips to the sent state.
            const result = await authClient.requestPasswordReset({ email })
            if (result.error) {
                throw new Error(
                    result.error.message ?? t.auth.sendResetLinkFailed,
                )
            }
            setSentTo(email)
        } catch (err) {
            toast.error(
                err instanceof Error ? err.message : t.auth.sendResetLinkFailed,
            )
        } finally {
            setSubmitting(false)
        }
    }

    if (sentTo !== null) {
        return (
            <AuthMessagePanel
                icon="mark_email_read"
                title={t.auth.resetPasswordTitle}
                subtitle={t.auth.resetEmailSent({ email: sentTo })}
                actionLabel={t.auth.backToSignIn}
                onAction={onBack}
            >
                <p className="m3-body-small mt-3 font-semibold leading-snug text-on-surface-variant">
                    {t.auth.resetEmailSentReturnHint}
                </p>
            </AuthMessagePanel>
        )
    }

    return (
        <AuthPanel>
            <AuthPanelTitle
                icon="lock_reset"
                title={t.auth.resetPasswordTitle}
                subtitle={t.auth.resetPasswordSubtitle}
            />
            <form
                className="mt-4.5 flex flex-col gap-4"
                onSubmit={handleSubmit}
            >
                <AuthTextField
                    icon="alternate_email"
                    name="email"
                    type="email"
                    label={t.auth.email}
                    autoComplete="email"
                    isRequired
                    isDisabled={submitting}
                />
                <AuthPrimaryButton
                    type="submit"
                    submitting={submitting}
                    label={t.auth.sendResetLink}
                />
                <div className="flex justify-center">
                    <Button
                        type="button"
                        variant="text"
                        isDisabled={submitting}
                        onPress={onBack}
                    >
                        {t.auth.backToSignIn}
                    </Button>
                </div>
            </form>
        </AuthPanel>
    )
}
