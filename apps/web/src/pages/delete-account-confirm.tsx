import { Button } from 'actify'
import { type FormEvent, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
    AuthFrame,
    AuthMessagePanel,
    AuthPanel,
    AuthPanelTitle,
    AuthPrimaryButton,
    AuthTextField,
} from '@/components/auth/auth-scaffold'
import { authClient } from '@/lib/auth-client'
import { useT } from '@/lib/i18n'

// Landing page for the emailed deletion link. Guard-free (see router.tsx):
// the link can be opened with or without a session. Possession of the token
// is the authorization — confirming here is final and irreversible.
export function DeleteAccountConfirm() {
    const t = useT()
    const navigate = useNavigate()
    const [searchParams] = useSearchParams()
    const token = searchParams.get('token')

    // The word is typed by the user, so it follows the app's language.
    const confirmWord = t.deleteAccount.confirmWord

    const [typedWord, setTypedWord] = useState('')
    const [loading, setLoading] = useState(false)
    const [done, setDone] = useState(false)
    // The token is single-use: if the submit fails with invalid_token the
    // link is dead even though it's still in the URL.
    const [tokenSpent, setTokenSpent] = useState(false)

    const invalidLink = !token || tokenSpent

    const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault()
        if (!token || typedWord !== confirmWord) return

        setLoading(true)
        try {
            const res = await fetch(
                `${import.meta.env.VITE_CONVEX_SITE_URL}/v1/account-deletion/confirm`,
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ token }),
                },
            )
            if (res.status === 400) {
                setTokenSpent(true)
                return
            }
            if (!res.ok) {
                throw new Error(t.deleteAccount.deleteFailed)
            }

            setDone(true)
            toast.success(t.deleteAccount.doneTitle)
            // Clear any local session state — the server already revoked
            // every session, so this can only fail harmlessly.
            try {
                await authClient.signOut()
            } catch {
                // The account no longer exists; a failed sign-out is expected.
            }
        } catch (err) {
            toast.error(
                err instanceof Error
                    ? err.message
                    : t.deleteAccount.deleteFailed,
            )
        } finally {
            setLoading(false)
        }
    }

    if (done) {
        return (
            <AuthFrame>
                <AuthMessagePanel
                    icon="check_circle"
                    title={t.deleteAccount.doneTitle}
                    subtitle={t.deleteAccount.doneBody}
                    actionLabel={t.deleteAccount.backHome}
                    onAction={() => navigate('/')}
                />
            </AuthFrame>
        )
    }

    if (invalidLink) {
        return (
            <AuthFrame>
                <AuthMessagePanel
                    icon="link_off"
                    title={t.deleteAccount.invalidTitle}
                    subtitle={t.deleteAccount.invalidBody}
                    actionLabel={t.deleteAccount.requestNewLink}
                    onAction={() => navigate('/delete-account')}
                />
            </AuthFrame>
        )
    }

    return (
        <AuthFrame>
            <AuthPanel>
                <AuthPanelTitle
                    icon="warning"
                    title={t.deleteAccount.confirmTitle}
                    subtitle={t.deleteAccount.confirmSubtitle}
                />

                <div className="mt-4 rounded-2xl bg-error-container px-4 py-3 text-on-error-container">
                    <p className="m3-body-medium font-semibold">
                        {t.deleteAccount.willDeleteTitle}
                    </p>
                    <ul className="m3-body-medium mt-2 list-disc space-y-1 pl-5">
                        <li>{t.deleteAccount.willDeleteTransactions}</li>
                        <li>{t.deleteAccount.willDeleteAccounts}</li>
                        <li>{t.deleteAccount.willDeleteCategories}</li>
                        <li>{t.deleteAccount.willDeleteUser}</li>
                    </ul>
                </div>

                <form
                    className="mt-4.5 flex flex-col gap-4"
                    onSubmit={handleSubmit}
                >
                    <AuthTextField
                        icon="keyboard"
                        name="confirm-word"
                        label={`${t.deleteAccount.confirmPrompt} ${confirmWord}`}
                        autoComplete="off"
                        value={typedWord}
                        onChange={setTypedWord}
                        isRequired
                        isDisabled={loading}
                    />
                    <AuthPrimaryButton
                        type="submit"
                        submitting={loading}
                        disabled={typedWord !== confirmWord}
                        label={t.deleteAccount.confirmSubmit}
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
