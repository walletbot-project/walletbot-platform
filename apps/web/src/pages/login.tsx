import { api } from '@wallet-bot/backend/api'
import { CURRENT_LEGAL_VERSION } from '@wallet-bot/shared'
import { Button } from 'actify'
import { useQuery } from 'convex/react'
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
import { TermsCheckbox } from '@/components/auth/terms-checkbox'
import { authClient } from '@/lib/auth-client'
import { signUpWithEmail } from '@/lib/auth-signup'
import { type Messages, useT } from '@/lib/i18n'
import { ForgotPasswordPanel } from '@/pages/auth/forgot-password-panel'
import { VerifyPendingPanel } from '@/pages/auth/verify-pending-panel'

type AuthMode = 'sign-in' | 'sign-up'

/**
 * Which panel the screen shows. `credentials` is the sign-in/sign-up form;
 * the other two replace it entirely until the user navigates back — the same
 * `_RemoteFlow` the native login screen switches on.
 */
type RemoteFlow = 'credentials' | 'forgot-password' | 'verify-pending'

/**
 * Sign-in failures, rendered from better-auth's `error.code`.
 *
 * Never from `error.message`: the auth server answers in English and knows
 * nothing about the client's locale, so folding that message into a localized
 * sentence produced half-English copy ("Invalid email or password. Si te
 * registraste con Google, usá…"). The codes are better-auth's `BASE_ERROR_CODES`.
 * `EMAIL_NOT_VERIFIED` never arrives here — the caller turns it into a flow
 * change instead.
 */
const signInErrorMessage = (code: string | undefined, t: Messages): string => {
    switch (code) {
        // A malformed address; signing up with Google is not a plausible
        // explanation, so this one skips the hint.
        case 'INVALID_EMAIL':
            return t.auth.invalidEmail
        // Wrong password, unknown address, and an address with no password
        // account all collapse into this single code — which is exactly what
        // makes the generic hint safe, since it discloses neither whether the
        // email exists nor which provider it uses.
        case 'INVALID_EMAIL_OR_PASSWORD':
            return t.auth.googleHint({ message: t.auth.invalidCredentials })
        // Anything unnamed (session creation, misconfiguration, a transport
        // failure with no code): still worth the hint, since a Google-only
        // account remains a plausible cause.
        default:
            return t.auth.googleHint({ message: t.auth.authFailed })
    }
}

export function Login({ mode }: { mode: AuthMode }) {
    const location = useLocation()
    const navigate = useNavigate()
    const t = useT()
    const from = location.state?.from?.pathname || '/'

    // The documents version in force right now, so a policy published on the
    // backend is recorded correctly without waiting for a web deploy. Falls
    // back to the bundled constant while the query is in flight or offline —
    // an older version simply means the gate re-prompts after sign-up.
    const policy = useQuery(api.v1.legal.queries.getPolicy)
    const legalVersion = policy?.currentVersion ?? CURRENT_LEGAL_VERSION

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
                    setError(signInErrorMessage(result.error.code, t))
                    return
                }

                navigate(from, { replace: true })
                return
            }

            // The submit button stays disabled until the box is ticked; this
            // guards the FormData path against anything that bypasses it.
            if (formData.get('termsAccepted') !== 'accepted') {
                setError(t.auth.termsRequired)
                return
            }

            // Posts to the backend's own sign-up endpoint (not
            // authClient.signUp.email) so a re-sign-up of an unverified
            // address re-sends the link instead of stranding the user on the
            // verify screen waiting for mail better-auth never sent — see
            // lib/auth-signup.ts. No callbackURL: the verification link's
            // landing page is canonicalized server-side to /verify-email.
            const outcome = await signUpWithEmail({
                name: name || email,
                email,
                password,
                // Recorded in `termsAcceptances` by the endpoint itself
                // (packages/backend/convex/authNative/http.ts).
                termsAcceptedVersion: legalVersion,
            })

            switch (outcome.status) {
                case 'verify-pending':
                    // No session yet (verification required) — for a new
                    // account and an unverified re-send alike. Either way an
                    // email really went out.
                    setPendingEmail(email)
                    setFlow('verify-pending')
                    return
                case 'account-exists':
                    setError(t.auth.accountExists)
                    return
                case 'rate-limited':
                    setError(t.auth.rateLimited)
                    return
                case 'email-send-failed':
                    setError(t.auth.emailSendFailed)
                    return
                case 'error':
                    // Everything the endpoint does not name by code
                    // (`bad_request`, `sign_up_failed`, a transport failure):
                    // its `message` carries better-auth's English text or raw
                    // server copy, so it goes to the console, not the screen.
                    console.error('sign-up failed', outcome.message)
                    setError(t.auth.signUpFailed)
                    return
            }
        } catch (err) {
            // Only genuine exceptions land here — both branches above report
            // their own failures. There is no server code to name, so keep it
            // generic rather than surfacing an untranslated `err.message`.
            console.error('auth request threw', err)
            setError(t.auth.connectionFailed)
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
    const [termsAccepted, setTermsAccepted] = useState(false)

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
                    <TermsCheckbox
                        isSelected={termsAccepted}
                        onChange={setTermsAccepted}
                        isDisabled={submitting}
                    />
                )}

                {error ? <AuthErrorNote message={error} /> : null}

                <AuthPrimaryButton
                    type="submit"
                    submitting={loading === 'email'}
                    isDisabled={mode === 'sign-up' && !termsAccepted}
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
