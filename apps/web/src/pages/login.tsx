import { Button } from 'actify'
import { type FormEvent, useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'

import googleIcon from '@/assets/google.svg'
import {
    AuthErrorNote,
    AuthFrame,
    AuthOrDivider,
    AuthPanel,
    AuthPanelTitle,
    AuthPrimaryButton,
    AuthTextField,
} from '@/components/auth/auth-scaffold'
import { authClient } from '@/lib/auth-client'
import { useT } from '@/lib/i18n'
import { ForgotPasswordPanel } from '@/pages/auth/forgot-password-panel'
import { VerifyPendingPanel } from '@/pages/auth/verify-pending-panel'

type AuthMode = 'sign-in' | 'sign-up'

/**
 * Which panel the screen shows. `credentials` is the sign-in/sign-up form;
 * the other two replace it entirely until the user navigates back — the same
 * `_RemoteFlow` the native login screen switches on.
 */
type RemoteFlow = 'credentials' | 'forgot-password' | 'verify-pending'

export function Login({ mode }: { mode: AuthMode }) {
    const location = useLocation()
    const navigate = useNavigate()
    const t = useT()
    const from = location.state?.from?.pathname || '/'

    const [loading, setLoading] = useState<'email' | 'google' | null>(null)
    const [error, setError] = useState<string | null>(null)
    const [flow, setFlow] = useState<RemoteFlow>('credentials')
    /** Email echoed in the copy of the verify-pending panel. */
    const [pendingEmail, setPendingEmail] = useState('')

    // Sign-in and create are separate routes; clear any stale error as the user
    // moves between them.
    const goToMode = (next: AuthMode) => {
        if (next === mode) return
        setError(null)
        navigate(next === 'sign-in' ? '/login' : '/signup', {
            state: location.state,
            replace: true,
        })
    }

    const handleGoogleSignIn = async () => {
        setError(null)
        setLoading('google')
        try {
            const result = await authClient.signIn.social({
                provider: 'google',
                callbackURL: window.location.origin + from,
            })
            if (result.error) {
                throw new Error(result.error.message ?? t.auth.authFailed)
            }
            // Success hands the tab to the provider redirect — keep the button
            // in its loading state until the navigation lands.
        } catch (err) {
            // Without this, a failed start left every control disabled on
            // "Signing in…" with no message, forever.
            setError(err instanceof Error ? err.message : String(err))
            setLoading(null)
        }
    }

    const handleEmailSubmit = async (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault()
        setError(null)
        setLoading('email')

        const formData = new FormData(event.currentTarget)
        const email = String(formData.get('email') ?? '').trim()
        const password = String(formData.get('password') ?? '')
        const name = String(formData.get('name') ?? '').trim()

        try {
            if (mode === 'sign-in') {
                const result = await authClient.signIn.email({
                    email,
                    password,
                    callbackURL: window.location.origin + from,
                })

                if (result.error) {
                    // The backend already re-sent the verification email on
                    // this attempt (sendOnSignIn).
                    if (result.error.code === 'EMAIL_NOT_VERIFIED') {
                        setPendingEmail(email)
                        setFlow('verify-pending')
                        return
                    }
                    throw new Error(result.error.message ?? t.auth.authFailed)
                }

                navigate(from, { replace: true })
                return
            }

            // No callbackURL: the verification link's landing page is
            // canonicalized server-side to /verify-email.
            const result = await authClient.signUp.email({
                name: name || email,
                email,
                password,
            })

            if (result.error) {
                throw new Error(result.error.message ?? t.auth.authFailed)
            }

            // With email verification required there is no session yet — for
            // new and already-registered emails alike (anti-enumeration).
            setPendingEmail(email)
            setFlow('verify-pending')
        } catch (err) {
            const message = err instanceof Error ? err.message : String(err)
            // Generic, account-independent hint so users who actually signed up
            // with Google are nudged toward it — without disclosing whether the
            // email exists or which provider it uses.
            setError(
                mode === 'sign-in' ? t.auth.googleHint({ message }) : message,
            )
        } finally {
            setLoading(null)
        }
    }

    const returnToSignIn = () => {
        setFlow('credentials')
        setError(null)
        if (mode !== 'sign-in') {
            navigate('/login', { state: location.state, replace: true })
        }
    }

    return (
        <AuthFrame>
            {flow === 'forgot-password' ? (
                <ForgotPasswordPanel onBack={returnToSignIn} />
            ) : flow === 'verify-pending' ? (
                <VerifyPendingPanel
                    email={pendingEmail}
                    onSignIn={returnToSignIn}
                />
            ) : (
                <CredentialsPanel
                    mode={mode}
                    loading={loading}
                    error={error}
                    onSubmit={handleEmailSubmit}
                    onGoogle={() => void handleGoogleSignIn()}
                    onModeChange={goToMode}
                    onForgotPassword={() => {
                        setError(null)
                        setFlow('forgot-password')
                    }}
                />
            )}
        </AuthFrame>
    )
}

/** The email form plus the Google action, porting `_RemoteLoginPanel`. */
function CredentialsPanel({
    mode,
    loading,
    error,
    onSubmit,
    onGoogle,
    onModeChange,
    onForgotPassword,
}: {
    mode: AuthMode
    loading: 'email' | 'google' | null
    error: string | null
    onSubmit: (event: FormEvent<HTMLFormElement>) => void
    onGoogle: () => void
    onModeChange: (mode: AuthMode) => void
    onForgotPassword: () => void
}) {
    const t = useT()
    const submitting = loading !== null
    const nameRef = useRef<HTMLDivElement>(null)

    // The name field only exists in sign-up; focus it when it appears so the
    // mode switch lands the caret where typing continues.
    useEffect(() => {
        if (mode !== 'sign-up') return
        nameRef.current?.querySelector('input')?.focus()
    }, [mode])

    return (
        <AuthPanel>
            <AuthPanelTitle
                icon="sync"
                title={t.auth.withAccount}
                subtitle={t.auth.withAccountDescription}
            />

            <form className="mt-4.5 flex flex-col gap-3" onSubmit={onSubmit}>
                {mode === 'sign-up' ? (
                    <div ref={nameRef}>
                        <AuthTextField
                            icon="badge"
                            name="name"
                            label={t.auth.name}
                            autoComplete="name"
                            isDisabled={submitting}
                        />
                    </div>
                ) : null}

                <AuthTextField
                    icon="alternate_email"
                    name="email"
                    type="email"
                    label={t.auth.email}
                    autoComplete="email"
                    isRequired
                    isDisabled={submitting}
                />

                <AuthTextField
                    icon="lock"
                    name="password"
                    type="password"
                    label={t.auth.password}
                    autoComplete={
                        mode === 'sign-in' ? 'current-password' : 'new-password'
                    }
                    minLength={8}
                    isRequired
                    isDisabled={submitting}
                />

                {mode === 'sign-in' ? (
                    <div className="-mt-1 flex justify-end">
                        <Button
                            type="button"
                            variant="text"
                            isDisabled={submitting}
                            onPress={onForgotPassword}
                        >
                            {t.auth.forgotPassword}
                        </Button>
                    </div>
                ) : (
                    <div className="h-1" />
                )}

                {error ? <AuthErrorNote message={error} /> : null}

                <AuthPrimaryButton
                    type="submit"
                    submitting={loading === 'email'}
                    label={mode === 'sign-in' ? t.auth.signIn : t.auth.signUp}
                />

                <div className="flex justify-center">
                    <Button
                        type="button"
                        variant="text"
                        isDisabled={submitting}
                        onPress={() =>
                            onModeChange(
                                mode === 'sign-in' ? 'sign-up' : 'sign-in',
                            )
                        }
                    >
                        {mode === 'sign-in'
                            ? t.auth.needAccountSignUp
                            : t.auth.haveAccountSignIn}
                    </Button>
                </div>
            </form>

            <div className="my-4.5">
                <AuthOrDivider label={t.auth.or} />
            </div>

            <Button
                variant="outlined"
                className="w-full bg-surface"
                style={{
                    height: 54,
                    '--md-outlined-button-container-shape': '16px',
                    '--md-outlined-button-outline-color':
                        'var(--md-sys-color-outline-variant)',
                }}
                onPress={onGoogle}
                isDisabled={submitting}
            >
                <img src={googleIcon} alt="" className="size-5" />
                {loading === 'google'
                    ? t.auth.signingIn
                    : t.auth.continueWithGoogle}
            </Button>
        </AuthPanel>
    )
}
