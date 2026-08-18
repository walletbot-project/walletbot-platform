import { type FormEvent, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
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
import { authClient } from '@/lib/auth-client'
import { useT } from '@/lib/i18n'

export function ResetPassword() {
    const t = useT()
    const navigate = useNavigate()
    const [searchParams] = useSearchParams()
    const token = searchParams.get('token')
    const linkError = searchParams.get('error')

    const [loading, setLoading] = useState(false)
    const [error, setError] = useState<string | null>(null)
    // The token is single-use: if the submit fails with INVALID_TOKEN the
    // link is dead even though it's still in the URL.
    const [tokenSpent, setTokenSpent] = useState(false)

    const invalidLink = !token || linkError !== null || tokenSpent

    const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault()
        if (!token) return
        setError(null)

        const formData = new FormData(event.currentTarget)
        const newPassword = String(formData.get('password') ?? '')
        const confirm = String(formData.get('confirm') ?? '')

        if (newPassword !== confirm) {
            setError(t.auth.passwordsDoNotMatch)
            return
        }

        setLoading(true)
        try {
            const result = await authClient.resetPassword({
                newPassword,
                token,
            })
            if (result.error) {
                if (result.error.code === 'INVALID_TOKEN') {
                    setTokenSpent(true)
                    return
                }
                throw new Error(
                    result.error.message ?? t.auth.resetPasswordFailed,
                )
            }
            toast.success(t.auth.passwordUpdated)
            navigate('/login', { replace: true })
        } catch (err) {
            setError(
                err instanceof Error ? err.message : t.auth.resetPasswordFailed,
            )
        } finally {
            setLoading(false)
        }
    }

    if (invalidLink) {
        return (
            <AuthFrame>
                <AuthMessagePanel
                    icon="link_off"
                    title={t.auth.invalidLinkTitle}
                    subtitle={t.auth.invalidLinkDescription}
                    actionLabel={t.auth.requestNewLink}
                    onAction={() => navigate('/forgot-password')}
                />
            </AuthFrame>
        )
    }

    return (
        <AuthFrame>
            <AuthPanel>
                <AuthPanelTitle
                    icon="lock_reset"
                    title={t.auth.newPasswordTitle}
                    subtitle={t.auth.newPasswordSubtitle}
                />
                <form
                    className="mt-4.5 flex flex-col gap-3"
                    onSubmit={handleSubmit}
                >
                    <AuthTextField
                        icon="lock"
                        name="password"
                        type="password"
                        label={t.auth.newPassword}
                        autoComplete="new-password"
                        minLength={8}
                        isRequired
                        isDisabled={loading}
                    />
                    <AuthTextField
                        icon="lock"
                        name="confirm"
                        type="password"
                        label={t.auth.repeatPassword}
                        autoComplete="new-password"
                        minLength={8}
                        isRequired
                        isDisabled={loading}
                    />

                    {error ? <AuthErrorNote message={error} /> : null}

                    <AuthPrimaryButton
                        type="submit"
                        submitting={loading}
                        label={t.auth.resetPasswordAction}
                    />
                </form>
            </AuthPanel>
        </AuthFrame>
    )
}
