import { api } from '@wallet-bot/backend/api'
import { Button } from 'actify'
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
import { useAuth } from '@/hooks/use-auth'
import { useFormatLocale, useT } from '@/lib/i18n'

/**
 * Renders the server's legal-acceptance verdict for the signed-in account
 * (see `v1/legal/queries:getMyAcceptance` and the policy in
 * packages/shared/src/legal.ts):
 *
 * - `ok` → the app;
 * - `reacceptRequired` → blocking acceptance panel (never accepted, below
 *   the min floor, or the grace deadline passed);
 * - anything else → the same panel with a "Not now" escape, once per page
 *   load — `reacceptRequested` today, and by contract any status this build
 *   doesn't recognize, so a future state can never hard-block an old client.
 *
 * Either panel can also sign out: declining the documents has to be possible,
 * and the gate replaces the whole app, account menu included.
 *
 * Propagation: the query is reactive to the acceptance ROW, not to the policy,
 * which lives in code. Convex subscriptions are invalidated by writes to the
 * data a query read, and deploying new function code writes nothing — so a
 * newly published version reaches a tab that is already open on its next load
 * or reconnect, not the instant of the deploy. Accepted behaviour (owner,
 * 2026-08-21); native is the same, one relaunch.
 */
export function TermsGate({ children }: { children: ReactNode }) {
    const acceptance = useQuery(api.v1.legal.queries.getMyAcceptance)
    // "Not now" on the soft prompt, remembered per page load and per
    // documents version: a reload (or a newer version) prompts again.
    const [dismissedVersion, setDismissedVersion] = useState<string | null>(
        null,
    )

    // Same contract as AuthGuard's initial load: render nothing until the
    // status is known, so the app never flashes ahead of the gate.
    if (acceptance === undefined) return null
    if (acceptance.status === 'ok') return <>{children}</>

    const blocking = acceptance.status === 'reacceptRequired'
    if (!blocking && dismissedVersion === acceptance.currentVersion) {
        return <>{children}</>
    }
    return (
        <TermsGatePanel
            currentVersion={acceptance.currentVersion}
            graceEndsAt={acceptance.graceEndsAt}
            onDismiss={
                blocking
                    ? null
                    : () => setDismissedVersion(acceptance.currentVersion)
            }
        />
    )
}

function TermsGatePanel({
    currentVersion,
    graceEndsAt,
    onDismiss,
}: {
    currentVersion: string
    graceEndsAt: number | null
    /** Present on the soft prompt only; `null` means blocking. */
    onDismiss: (() => void) | null
}) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const auth = useAuth()
    const accept = useMutation(api.v1.legal.mutations.accept)
    const [accepted, setAccepted] = useState(false)
    const [submitting, setSubmitting] = useState(false)
    const [signingOut, setSigningOut] = useState(false)
    const [error, setError] = useState<string | null>(null)
    const busy = submitting || signingOut

    const handleContinue = async () => {
        setError(null)
        setSubmitting(true)
        try {
            await accept({ documentVersion: currentVersion })
            // No setSubmitting(false): the query above flips the status and
            // unmounts this panel; dropping the spinner early would flicker.
        } catch {
            setError(t.auth.termsAcceptFailed)
            setSubmitting(false)
        }
    }

    // The way out for someone who does not want to accept. Without it the
    // blocking gate has no exit at all: it replaces the whole app, including
    // the account menu that holds the only other sign-out.
    const handleSignOut = async () => {
        setError(null)
        setSigningOut(true)
        try {
            await auth.signOut()
            // No reset on success: signing out unmounts this panel (the guard
            // above it redirects to /login).
        } catch {
            setError(t.auth.termsSignOutFailed)
            setSigningOut(false)
        }
    }

    const deadline =
        onDismiss !== null && graceEndsAt !== null
            ? new Intl.DateTimeFormat(formatLocale, {
                  dateStyle: 'long',
              }).format(new Date(graceEndsAt))
            : null

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
                        {deadline ? (
                            <p className="m3-body-small font-semibold text-on-surface-variant">
                                {t.auth.termsDeadline({ date: deadline })}
                            </p>
                        ) : null}
                        <TermsCheckbox
                            isSelected={accepted}
                            onChange={setAccepted}
                            isDisabled={busy}
                        />
                        {error ? <AuthErrorNote message={error} /> : null}
                        <AuthPrimaryButton
                            label={t.auth.termsContinue}
                            submitting={submitting}
                            isDisabled={!accepted || signingOut}
                            onPress={() => void handleContinue()}
                        />
                        <div className="flex flex-wrap items-center justify-center gap-1">
                            {onDismiss !== null ? (
                                <Button
                                    type="button"
                                    variant="text"
                                    isDisabled={busy}
                                    onPress={onDismiss}
                                >
                                    {t.auth.termsLater}
                                </Button>
                            ) : null}
                            <Button
                                type="button"
                                variant="text"
                                isDisabled={busy}
                                onPress={() => void handleSignOut()}
                            >
                                {t.nav.signOut}
                            </Button>
                        </div>
                    </div>
                </AuthPanel>
            </div>
        </AuthScaffold>
    )
}
