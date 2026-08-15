import { Button, CircularProgress } from 'actify'
import { type FormEvent, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { toast } from 'sonner'

import googleIcon from '@/assets/google.svg'
import { Icon } from '@/components/m3/icon'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { authClient } from '@/lib/auth-client'
import { useT } from '@/lib/i18n'

type AuthMode = 'sign-in' | 'sign-up'

export function Login({ mode }: { mode: AuthMode }) {
    const location = useLocation()
    const navigate = useNavigate()
    const t = useT()
    const from = location.state?.from?.pathname || '/'

    const [loading, setLoading] = useState<'email' | 'google' | null>(null)
    const [error, setError] = useState<string | null>(null)
    // Set after a signup, or a sign-in blocked by verification: the account
    // exists but its email isn't verified yet, so we show the
    // check-your-inbox panel instead of the form.
    const [pendingEmail, setPendingEmail] = useState<string | null>(null)

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

    const handleGoogleSignIn = () => {
        setError(null)
        setLoading('google')
        authClient.signIn.social({
            provider: 'google',
            callbackURL: window.location.origin + from,
        })
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

    const handleResendVerification = () => {
        if (!pendingEmail) return
        // No callbackURL: canonicalized server-side to /verify-email.
        const promise = authClient
            .sendVerificationEmail({ email: pendingEmail })
            .then((result) => {
                if (result.error) {
                    throw new Error(
                        result.error.message ?? t.auth.resendVerificationFailed,
                    )
                }
            })
        toast.promise(promise, {
            loading: t.auth.resendingVerificationEmail,
            success: t.auth.verificationEmailResent,
            error: t.auth.resendVerificationFailed,
        })
    }

    if (pendingEmail) {
        return (
            <div className="flex min-h-dvh items-center justify-center bg-surface">
                <div className="flex w-full max-w-sm flex-col items-center gap-6 px-4 text-center">
                    <div className="rounded-full bg-surface-container-highest p-4">
                        <Icon
                            name="mark_email_read"
                            filled
                            size={24}
                            className="text-on-surface-variant"
                        />
                    </div>
                    <div className="flex flex-col gap-2">
                        <h1 className="m3-headline-small font-semibold">
                            {t.auth.verifyEmailTitle}
                        </h1>
                        <p className="m3-body-medium text-on-surface-variant">
                            {t.auth.verifyEmailSent({ email: pendingEmail })}{' '}
                            {t.auth.verifyEmailInstructions}
                        </p>
                    </div>
                    <div className="flex w-full flex-col gap-2">
                        <Button
                            variant="filled"
                            className="w-full"
                            onPress={handleResendVerification}
                        >
                            {t.auth.resendVerificationEmail}
                        </Button>
                        <Button
                            variant="text"
                            className="w-full"
                            onPress={() => setPendingEmail(null)}
                        >
                            {t.auth.backToSignIn}
                        </Button>
                    </div>
                </div>
            </div>
        )
    }

    return (
        <div className="flex min-h-dvh justify-center bg-surface px-5 py-6">
            <div className="flex w-full max-w-[480px] flex-col">
                {/* Hero header, matching the native login's `_HeroHeader`. */}
                <div className="flex items-center gap-3.5">
                    <span className="flex size-14 shrink-0 items-center justify-center rounded-[18px] bg-primary text-on-primary shadow-level-3">
                        <Icon name="account_balance_wallet" filled />
                    </span>
                    <div className="flex min-w-0 flex-col">
                        <h1 className="m3-headline-medium font-black">
                            {t.common.appName}
                        </h1>
                        <p className="m3-body-medium text-on-surface-variant">
                            {t.auth.signInToContinue}
                        </p>
                    </div>
                </div>

                <form
                    className="mt-6 flex w-full flex-col gap-4 rounded-[28px] bg-surface-container-low p-5"
                    onSubmit={handleEmailSubmit}
                >
                    {mode === 'sign-up' ? (
                        <div className="grid gap-2">
                            <Label htmlFor="name">{t.common.name}</Label>
                            <div className="relative">
                                <Icon
                                    name="person"
                                    filled
                                    size={16}
                                    className="-translate-y-1/2 pointer-events-none absolute top-1/2 left-2.5 text-on-surface-variant"
                                />
                                <Input
                                    id="name"
                                    name="name"
                                    autoComplete="name"
                                    placeholder={t.auth.namePlaceholder}
                                    className="pl-8"
                                    disabled={loading !== null}
                                />
                            </div>
                        </div>
                    ) : null}

                    <div className="grid gap-2">
                        <Label htmlFor="email">{t.auth.email}</Label>
                        <div className="relative">
                            <Icon
                                name="mail"
                                filled
                                size={16}
                                className="-translate-y-1/2 pointer-events-none absolute top-1/2 left-2.5 text-on-surface-variant"
                            />
                            <Input
                                id="email"
                                name="email"
                                type="email"
                                autoComplete="email"
                                placeholder="you@example.com"
                                className="pl-8"
                                required
                                disabled={loading !== null}
                            />
                        </div>
                    </div>

                    <div className="grid gap-2">
                        <Label htmlFor="password">{t.auth.password}</Label>
                        <div className="relative">
                            <Icon
                                name="lock"
                                filled
                                size={16}
                                className="-translate-y-1/2 pointer-events-none absolute top-1/2 left-2.5 text-on-surface-variant"
                            />
                            <Input
                                id="password"
                                name="password"
                                type="password"
                                autoComplete={
                                    mode === 'sign-in'
                                        ? 'current-password'
                                        : 'new-password'
                                }
                                placeholder={
                                    mode === 'sign-in'
                                        ? t.auth.passwordPlaceholder
                                        : t.auth.newPasswordPlaceholder
                                }
                                className="pl-8"
                                minLength={8}
                                required
                                disabled={loading !== null}
                            />
                        </div>
                    </div>

                    {mode === 'sign-in' ? (
                        <Link
                            to="/forgot-password"
                            className="m3-label-large -mt-2 self-end text-primary underline-offset-4 hover:underline"
                        >
                            {t.auth.forgotPassword}
                        </Link>
                    ) : null}

                    {error ? (
                        <p className="m3-body-medium rounded-lg bg-error-container px-3 py-2 text-on-error-container">
                            {error}
                        </p>
                    ) : null}

                    <Button
                        type="submit"
                        variant="filled"
                        className="w-full"
                        // The native login gives its primary action a taller,
                        // squarer shape than the M3 default pill.
                        style={{
                            height: 54,
                            '--md-filled-button-container-shape': '16px',
                        }}
                        isDisabled={loading !== null}
                    >
                        {loading === 'email' ? (
                            <CircularProgress isIndeterminate size="xs" />
                        ) : null}
                        {mode === 'sign-in' ? t.auth.signIn : t.auth.signUp}
                    </Button>

                    <Button
                        type="button"
                        variant="text"
                        className="self-center"
                        onPress={() =>
                            goToMode(mode === 'sign-in' ? 'sign-up' : 'sign-in')
                        }
                    >
                        {mode === 'sign-in'
                            ? t.auth.needAccountSignUp
                            : t.auth.haveAccountSignIn}
                    </Button>
                </form>

                <div className="mt-4.5 flex w-full items-center gap-3">
                    <Separator className="flex-1" />
                    <span className="m3-label-medium font-bold text-on-surface-variant">
                        {t.auth.or}
                    </span>
                    <Separator className="flex-1" />
                </div>

                <Button
                    variant="outlined"
                    className="mt-4.5 w-full"
                    style={{
                        height: 54,
                        '--md-outlined-button-container-shape': '16px',
                    }}
                    onPress={handleGoogleSignIn}
                    isDisabled={loading !== null}
                >
                    {loading === 'google' ? (
                        <CircularProgress isIndeterminate size="xs" />
                    ) : (
                        <img
                            src={googleIcon}
                            alt="Google"
                            className="h-5 w-5"
                        />
                    )}
                    {loading === 'google'
                        ? t.auth.signingIn
                        : t.auth.continueWithGoogle}
                </Button>
            </div>
        </div>
    )
}
