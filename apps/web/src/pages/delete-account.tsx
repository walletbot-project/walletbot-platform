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
import { useT } from '@/lib/i18n'

// Guard-free page (see router.tsx): works logged in (reached from the settings
// tile, email prefilled) and logged out (Play's data-deletion policy requires
// a web-accessible deletion URL). The endpoint never discloses whether the
// email exists.
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

        try {
            const res = await fetch(
                `${import.meta.env.VITE_CONVEX_SITE_URL}/v1/account-deletion/request`,
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email }),
                },
            )
            if (!res.ok) {
                const body = (await res.json().catch(() => null)) as {
                    message?: string
                } | null
                throw new Error(body?.message ?? t.deleteAccount.sendFailed)
            }
            setSentTo(email)
        } catch (err) {
            toast.error(
                err instanceof Error ? err.message : t.deleteAccount.sendFailed,
            )
        } finally {
            setLoading(false)
        }
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
                    // With a session the address is provably the user's own, so
                    // there is nothing to protect by hedging. Anonymous callers
                    // keep the non-committal wording.
                    subtitle={
                        session
                            ? t.deleteAccount.sentDefinite({ email: sentTo })
                            : t.deleteAccount.sentGeneric({ email: sentTo })
                    }
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
