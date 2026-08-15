import { Button } from 'actify'
import { useEffect, useState } from 'react'
import {
    AuthPanel,
    AuthPanelTitle,
    AuthPrimaryButton,
} from '@/components/auth/auth-scaffold'
import { resendVerificationEmail } from '@/lib/auth-verification'
import { useT } from '@/lib/i18n'

/** Seconds the resend action stays disabled after a send. */
const RESEND_COOLDOWN_SECONDS = 30

/**
 * Shown after a sign-up, or a sign-in blocked by an unverified email — the
 * native `_VerifyEmailPendingPanel`. The cooldown is UX throttling only: the
 * backend re-sends on blocked sign-in attempts regardless.
 */
export function VerifyPendingPanel({
    email,
    onSignIn,
}: {
    email: string
    onSignIn: () => void
}) {
    const t = useT()
    const [submitting, setSubmitting] = useState(false)
    const [cooldown, setCooldown] = useState(0)

    useEffect(() => {
        if (cooldown <= 0) return
        const timer = window.setTimeout(
            () => setCooldown((current) => current - 1),
            1000,
        )
        return () => window.clearTimeout(timer)
    }, [cooldown])

    const handleResend = async () => {
        setSubmitting(true)
        try {
            await resendVerificationEmail(email, t)
            setCooldown(RESEND_COOLDOWN_SECONDS)
        } catch {
            // Already surfaced by the toast in resendVerificationEmail.
        } finally {
            setSubmitting(false)
        }
    }

    return (
        <AuthPanel>
            <AuthPanelTitle
                icon="mark_email_unread"
                title={t.auth.verifyEmailTitle}
                subtitle={t.auth.verifyEmailSent({ email })}
            />
            <p className="m3-body-small mt-3 font-semibold leading-snug text-on-surface-variant">
                {t.auth.verifyEmailInstructions}
            </p>
            <div className="mt-4">
                <AuthPrimaryButton
                    submitting={submitting}
                    label={t.auth.verifyEmailDone}
                    onPress={onSignIn}
                />
            </div>
            <div className="mt-2.5 flex justify-center">
                <Button
                    type="button"
                    variant="text"
                    isDisabled={cooldown > 0 || submitting}
                    onPress={handleResend}
                >
                    {cooldown > 0
                        ? t.auth.resendVerificationCooldown({
                              seconds: cooldown,
                          })
                        : t.auth.resendVerificationEmail}
                </Button>
            </div>
        </AuthPanel>
    )
}
