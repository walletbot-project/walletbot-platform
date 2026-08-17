import { LoaderCircle, Lock, Mail, UserRound } from 'lucide-react'
import { type FormEvent, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'

import googleIcon from '@/assets/google.svg'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { authClient } from '@/lib/auth-client'
import { trackMetric } from '@/lib/telemetry'

type AuthMode = 'sign-in' | 'sign-up'

export function Login({ mode }: { mode: AuthMode }) {
    const location = useLocation()
    const navigate = useNavigate()
    const from = location.state?.from?.pathname || '/'

    const [loading, setLoading] = useState<'email' | 'google' | null>(null)
    const [error, setError] = useState<string | null>(null)

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
            const result =
                mode === 'sign-in'
                    ? await authClient.signIn.email({
                          email,
                          password,
                          callbackURL: window.location.origin + from,
                      })
                    : await authClient.signUp.email({
                          name: name || email,
                          email,
                          password,
                          callbackURL: window.location.origin + from,
                      })

            if (result.error) {
                throw new Error(result.error.message ?? 'No se pudo autenticar')
            }

            if (mode === 'sign-in') {
                void trackMetric('business.user_accounts.signed_in_count', {
                    type: 'counter',
                    value: 1,
                    unit: 'count',
                    attributes: {
                        auth_method: 'email_password',
                        client_platform: 'web',
                    },
                })
            }

            navigate(from, { replace: true })
        } catch (err) {
            const message = err instanceof Error ? err.message : String(err)
            // Generic, account-independent hint so users who actually signed up
            // with Google are nudged toward it — without disclosing whether the
            // email exists or which provider it uses.
            setError(
                mode === 'sign-in'
                    ? `${message}. Si te registraste con Google, usá "Continuar con Google".`
                    : message,
            )
        } finally {
            setLoading(null)
        }
    }

    return (
        <div className="flex min-h-screen items-center justify-center bg-background">
            <div className="flex w-full max-w-sm flex-col items-center gap-6 px-4">
                <div className="flex flex-col items-center gap-2">
                    <h1 className="text-2xl font-semibold tracking-tight">
                        Wallet Bot
                    </h1>
                    <p className="text-sm text-muted-foreground">
                        Iniciá sesión para continuar
                    </p>
                </div>

                <div className="grid w-full grid-cols-2 rounded-lg border border-border bg-muted/40 p-1">
                    <Button
                        type="button"
                        variant={mode === 'sign-in' ? 'secondary' : 'ghost'}
                        size="sm"
                        aria-pressed={mode === 'sign-in'}
                        onClick={() => goToMode('sign-in')}
                    >
                        Iniciar sesión
                    </Button>
                    <Button
                        type="button"
                        variant={mode === 'sign-up' ? 'secondary' : 'ghost'}
                        size="sm"
                        aria-pressed={mode === 'sign-up'}
                        onClick={() => goToMode('sign-up')}
                    >
                        Crear cuenta
                    </Button>
                </div>

                <form
                    className="flex w-full flex-col gap-4"
                    onSubmit={handleEmailSubmit}
                >
                    {mode === 'sign-up' ? (
                        <div className="grid gap-2">
                            <Label htmlFor="name">Nombre</Label>
                            <div className="relative">
                                <UserRound className="-translate-y-1/2 pointer-events-none absolute top-1/2 left-2.5 size-4 text-muted-foreground" />
                                <Input
                                    id="name"
                                    name="name"
                                    autoComplete="name"
                                    placeholder="Tu nombre"
                                    className="pl-8"
                                    disabled={loading !== null}
                                />
                            </div>
                        </div>
                    ) : null}

                    <div className="grid gap-2">
                        <Label htmlFor="email">Correo</Label>
                        <div className="relative">
                            <Mail className="-translate-y-1/2 pointer-events-none absolute top-1/2 left-2.5 size-4 text-muted-foreground" />
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
                        <Label htmlFor="password">Contraseña</Label>
                        <div className="relative">
                            <Lock className="-translate-y-1/2 pointer-events-none absolute top-1/2 left-2.5 size-4 text-muted-foreground" />
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
                                        ? 'Tu contraseña'
                                        : 'Al menos 8 caracteres'
                                }
                                className="pl-8"
                                minLength={8}
                                required
                                disabled={loading !== null}
                            />
                        </div>
                    </div>

                    {error ? (
                        <p className="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                            {error}
                        </p>
                    ) : null}

                    <Button
                        type="submit"
                        className="w-full"
                        disabled={loading !== null}
                    >
                        {loading === 'email' ? (
                            <LoaderCircle className="animate-spin" />
                        ) : null}
                        {mode === 'sign-in' ? 'Iniciar sesión' : 'Crear cuenta'}
                    </Button>
                </form>

                <div className="flex w-full items-center gap-3">
                    <Separator className="flex-1" />
                    <span className="text-xs text-muted-foreground">o</span>
                    <Separator className="flex-1" />
                </div>

                <Button
                    variant="outline"
                    className="w-full"
                    onClick={handleGoogleSignIn}
                    disabled={loading !== null}
                >
                    {loading === 'google' ? (
                        <LoaderCircle className="animate-spin" />
                    ) : (
                        <img
                            src={googleIcon}
                            alt="Google"
                            className="h-5 w-5"
                        />
                    )}
                    {loading === 'google'
                        ? 'Iniciando sesión...'
                        : 'Continuar con Google'}
                </Button>
            </div>
        </div>
    )
}
