import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { type ReactNode, useState } from 'react'
import {
    AuthErrorNote,
    AuthHeroHeader,
    AuthPanel,
    AuthPanelTitle,
    AuthPrimaryButton,
    AuthScaffold,
} from '@/components/auth/auth-scaffold'
import { TermsCheckbox } from '@/components/auth/terms-checkbox'
import { useT } from '@/lib/i18n'

/**
 * Blocks the app for authenticated accounts without a recorded acceptance of
 * the legal documents version currently in force — first Google sign-ins
 * (the OAuth redirect cannot carry the sign-up checkbox), accounts created
 * before the acceptance flow, and everyone again when the documents' version
 * bumps. Accounts whose acceptance was recorded at sign-up pass straight
 * through; accepting here records it and the reactive query lets them in.
 */
export function TermsGate({ children }: { children: ReactNode }) {
    const acceptance = useQuery(api.v1.legal.queries.getMyAcceptance)

    // Same contract as AuthGuard's initial load: render nothing until the
    // status is known, so the app never flashes ahead of the gate.
    if (acceptance === undefined) return null
    if (acceptance.accepted) return <>{children}</>
    return <TermsGatePanel currentVersion={acceptance.currentVersion} />
}

function TermsGatePanel({ currentVersion }: { currentVersion: string }) {
    const t = useT()
    const accept = useMutation(api.v1.legal.mutations.accept)
    const [accepted, setAccepted] = useState(false)
    const [submitting, setSubmitting] = useState(false)
    const [error, setError] = useState<string | null>(null)

    const handleContinue = async () => {
        setError(null)
        setSubmitting(true)
        try {
            await accept({ documentVersion: currentVersion })
            // No setSubmitting(false): the query above flips `accepted` and
            // unmounts this panel; dropping the spinner early would flicker.
        } catch {
            setError(t.auth.termsAcceptFailed)
            setSubmitting(false)
        }
    }

    return (
        <AuthScaffold>
            <AuthHeroHeader subtitle={t.auth.termsGateSubtitle} />
            <div className="mt-5.5">
                <AuthPanel>
                    <AuthPanelTitle
                        icon="verified_user"
                        title={t.auth.termsGateTitle}
                        subtitle={t.auth.termsGateDescription}
                    />
                    <div className="mt-4.5 flex flex-col gap-3">
                        <TermsCheckbox
                            isSelected={accepted}
                            onChange={setAccepted}
                            isDisabled={submitting}
                        />
                        {error ? <AuthErrorNote message={error} /> : null}
                        <AuthPrimaryButton
                            label={t.auth.termsContinue}
                            submitting={submitting}
                            isDisabled={!accepted}
                            onPress={() => void handleContinue()}
                        />
                    </div>
                </AuthPanel>
            </div>
        </AuthScaffold>
    )
}
