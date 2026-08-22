import { Button, CircularProgress } from 'actify'
import { type FormEvent, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
    AuthErrorNote,
    AuthFrame,
    AuthMessagePanel,
    AuthPanel,
    AuthPanelTitle,
    AuthPrimaryButton,
    AuthTextField,
} from '@/components/auth/auth-scaffold'
import { useCachedSession } from '@/hooks/use-cached-session'
import { requestAccountDeletion } from '@/lib/account-deletion'
import { useT } from '@/lib/i18n'

// Guard-free page (see router.tsx): works logged in (reached from the settings
// tile, email prefilled) and logged out (Play's data-deletion policy requires
// a web-accessible deletion URL). The endpoint reports exactly what happened,
// including whether the address has an account (docs/riesgos.md R-002).
export function DeleteAccount() {
    const t = useT()
    const navigate = useNavigate()
    const { session, isInitialLoading } = useCachedSession()
    const [loading, setLoading] = useState(false)
    const [sentTo, setSentTo] = useState<string | null>(null)

    const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault()
        setLoading(true)

        const email = String(
            new FormData(event.currentTarget).get('email') ?? '',
        )
            .trim()
            .toLowerCase()

        // Only a send the server confirmed flips to the sent panel. It used to
        // flip on any non-error response, and the endpoint answered `{ ok }`
        // for an unknown address, a throttled request, an already-deleted
        // account and a failed send alike — so the page cheerfully reported a
        // link it had never sent anywhere.
        const outcome = await requestAccountDeletion(email)
        switch (outcome.status) {
            case 'sent':
                setSentTo(email)
                break
            case 'account-not-found':
                toast.error(t.deleteAccount.accountNotFound({ email }))
                break
            case 'already-deleted':
                toast.error(t.deleteAccount.alreadyDeleted)
                break
            case 'rate-limited':
                toast.error(t.deleteAccount.rateLimited)
                break
            case 'email-send-failed':
                toast.error(t.deleteAccount.sendFailed)
                break
            case 'error':
                toast.error(outcome.message || t.deleteAccount.sendFailed)
                break
        }
        setLoading(false)
    }

    // The email field is uncontrolled, so `defaultValue` is only read at mount.
    // Rendering the form before the session settles would leave a logged-in
    // user with a blank field that never fills in.
    if (isInitialLoading) {
        return (
            <AuthFrame>
                <AuthPanel>
                    <div className="flex justify-center py-6">
                        <CircularProgress isIndeterminate size="md" />
                    </div>
                </AuthPanel>
            </AuthFrame>
        )
    }

    if (sentTo !== null) {
        return (
            <AuthFrame>
                <AuthMessagePanel
                    icon="mark_email_read"
                    title={t.deleteAccount.sentTitle}
                    // Reaching this panel now means the server confirmed the
                    // send, so the copy is definite for everyone. It used to
                    // pick the wording off the session, on the assumption that
                    // a signed-in user could only be requesting their own
                    // address — but the field is editable, so typing any
                    // address at all produced "we sent a link to <address>".
                    subtitle={t.deleteAccount.sentDefinite({ email: sentTo })}
                    actionLabel={t.deleteAccount.backHome}
                    onAction={() => navigate('/')}
                >
                    <p className="m3-body-small mt-3 font-semibold leading-snug text-on-surface-variant">
                        {t.deleteAccount.sentHint}
                    </p>
                </AuthMessagePanel>
            </AuthFrame>
        )
    }

    return (
        <AuthFrame>
            <AuthPanel>
                <AuthPanelTitle
                    icon="person_off"
                    title={t.deleteAccount.title}
                    subtitle={t.deleteAccount.subtitle}
                />
                <form
                    className="mt-4.5 flex flex-col gap-4"
                    onSubmit={handleSubmit}
                >
                    <AuthErrorNote message={t.deleteAccount.warning} />
                    <AuthTextField
                        icon="alternate_email"
                        name="email"
                        type="email"
                        label={t.deleteAccount.emailLabel}
                        autoComplete="email"
                        defaultValue={session?.user.email}
                        isRequired
                        isDisabled={loading}
                    />
                    <AuthPrimaryButton
                        type="submit"
                        submitting={loading}
                        label={t.deleteAccount.submit}
                    />
                    <div className="flex justify-center">
                        <Button
                            type="button"
                            variant="text"
                            isDisabled={loading}
                            onPress={() => navigate('/')}
                        >
                            {t.common.cancel}
                        </Button>
                    </div>
                </form>
            </AuthPanel>
        </AuthFrame>
    )
}
