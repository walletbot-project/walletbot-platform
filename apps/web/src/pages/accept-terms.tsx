import { api } from '@wallet-bot/backend/api'
import { Button } from 'actify'
import { useMutation } from 'convex/react'
import { useState } from 'react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'

import {
    AuthErrorNote,
    AuthFrame,
    AuthPanel,
    AuthPanelTitle,
    AuthPrimaryButton,
} from '@/components/auth/auth-scaffold'
import { LegalConsentChecks } from '@/components/auth/legal-consent'
import { useAuth } from '@/hooks/use-auth'
import {
    dismissLegalPrompt,
    isFirstAcceptance,
    legalDismissalKey,
    pendingLegalDocuments,
    useLegalAcceptance,
} from '@/hooks/use-legal-acceptance'
import { useI18n, useT } from '@/lib/i18n'

/**
 * The acceptance gate: the screen a signed-in user gets until they accept the
 * current Terms and Privacy Policy. Reached only through `LegalGuard`, and
 * bounces straight back out when there is nothing to accept.
 *
 * Vertically centred, on the same painted backdrop as the sign-in screens —
 * `AuthFrame` already does both.
 */
export function AcceptTerms() {
    const t = useT()
    const { locale } = useI18n()
    const navigate = useNavigate()
    const location = useLocation()
    const { user, signOut } = useAuth()
    const status = useLegalAcceptance()
    const accept = useMutation(api.v1.legal.mutations.accept)

    const [ageConfirmed, setAgeConfirmed] = useState(false)
    const [accepted, setAccepted] = useState(false)
    const [submitting, setSubmitting] = useState(false)
    const [error, setError] = useState<string | null>(null)

    const from = location.state?.from?.pathname || '/'

    if (status === undefined) return null
    // Accepted from another tab, or the user landed here by typing the URL.
    if (!status.prompt) return <Navigate to={from} replace />

    const pending = pendingLegalDocuments(status)
    const first = isFirstAcceptance(status)
    const title = first
        ? t.legal.firstTitle
        : pending.length > 1
          ? t.legal.updatedBothTitle
          : pending[0] === 'privacy'
            ? t.legal.updatedPrivacyTitle
            : t.legal.updatedTermsTitle
    const subtitle = first
        ? t.legal.firstSubtitle
        : status.blocking
          ? t.legal.updatedSubtitle
          : t.legal.updatedSubtitleGrace

    const handleAccept = async () => {
        setError(null)
        setSubmitting(true)
        try {
            await accept({
                documents: pending,
                ageConfirmed: true,
                platform: 'web',
                locale,
            })
            navigate(from, { replace: true })
        } catch (err) {
            // The mutation's own message is server copy in English; show the
            // localized line and keep the detail in the console.
            console.error('recording legal acceptance failed', err)
            setError(t.legal.acceptFailed)
        } finally {
            setSubmitting(false)
        }
    }

    const handleLater = () => {
        dismissLegalPrompt(legalDismissalKey(user.userId, status))
        navigate(from, { replace: true })
    }

    return (
        <AuthFrame>
            <AuthPanel>
                <AuthPanelTitle
                    icon="policy"
                    title={title}
                    subtitle={subtitle}
                />

                <div className="mt-4.5">
                    <LegalConsentChecks
                        documents={pending}
                        ageConfirmed={ageConfirmed}
                        accepted={accepted}
                        onAgeConfirmedChange={setAgeConfirmed}
                        onAcceptedChange={setAccepted}
                        disabled={submitting}
                    />
                </div>

                {error ? (
                    <div className="mt-3">
                        <AuthErrorNote message={error} />
                    </div>
                ) : null}

                <div className="mt-4.5">
                    <AuthPrimaryButton
                        label={t.legal.acceptAction}
                        submitting={submitting}
                        disabled={!ageConfirmed || !accepted}
                        onPress={() => void handleAccept()}
                    />
                </div>

                {/*
                 * No dead end. Inside the grace period the prompt can wait;
                 * once blocking, the only ways out are accepting or leaving
                 * the account — never a screen with nothing to press.
                 */}
                <div className="mt-1 flex justify-center gap-1">
                    {status.blocking ? null : (
                        <Button
                            type="button"
                            variant="text"
                            isDisabled={submitting}
                            onPress={handleLater}
                        >
                            {t.legal.later}
                        </Button>
                    )}
                    <Button
                        type="button"
                        variant="text"
                        isDisabled={submitting}
                        onPress={() => void signOut()}
                    >
                        {t.nav.signOut}
                    </Button>
                </div>
            </AuthPanel>
        </AuthFrame>
    )
}
