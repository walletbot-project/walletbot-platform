import { type FormEvent, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { LoaderCircle, Lock, Mail, UserRound } from 'lucide-react'

import googleIcon from '@/assets/google.svg'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { authClient } from '@/lib/auth-client'

export function Login() {
    const location = useLocation()
    const navigate = useNavigate()
    const from = location.state?.from?.pathname || '/'

    const [mode, setMode] = useState<'sign-in' | 'sign-up'>('sign-in')
    const [loading, setLoading] = useState<'email' | 'google' | null>(null)
    const [error, setError] = useState<string | null>(null)

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
                throw new Error(result.error.message ?? 'Authentication failed')
            }

            navigate(from, { replace: true })
        } catch (err) {
            setError(err instanceof Error ? err.message : String(err))
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
                        Sign in to continue
                    </p>
                </div>

                <div className="grid w-full grid-cols-2 rounded-lg border border-border bg-muted/40 p-1">
                    <Button
                        type="button"
                        variant={mode === 'sign-in' ? 'secondary' : 'ghost'}
                        size="sm"
                        aria-pressed={mode === 'sign-in'}
                        onClick={() => {
                            setMode('sign-in')
                            setError(null)
                        }}
                    >
                        Sign in
                    </Button>
                    <Button
                        type="button"
                        variant={mode === 'sign-up' ? 'secondary' : 'ghost'}
                        size="sm"
                        aria-pressed={mode === 'sign-up'}
                        onClick={() => {
                            setMode('sign-up')
                            setError(null)
                        }}
                    >
                        Create
                    </Button>
                </div>

                <form
                    className="flex w-full flex-col gap-4"
                    onSubmit={handleEmailSubmit}
                >
                    {mode === 'sign-up' ? (
                        <div className="grid gap-2">
                            <Label htmlFor="name">Name</Label>
                            <div className="relative">
                                <UserRound className="-translate-y-1/2 pointer-events-none absolute top-1/2 left-2.5 size-4 text-muted-foreground" />
                                <Input
                                    id="name"
                                    name="name"
                                    autoComplete="name"
                                    className="pl-8"
                                    disabled={loading !== null}
                                />
                            </div>
                        </div>
                    ) : null}

                    <div className="grid gap-2">
                        <Label htmlFor="email">Email</Label>
                        <div className="relative">
                            <Mail className="-translate-y-1/2 pointer-events-none absolute top-1/2 left-2.5 size-4 text-muted-foreground" />
                            <Input
                                id="email"
                                name="email"
                                type="email"
                                autoComplete="email"
                                className="pl-8"
                                required
                                disabled={loading !== null}
                            />
                        </div>
                    </div>

                    <div className="grid gap-2">
                        <Label htmlFor="password">Password</Label>
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
                        {mode === 'sign-in' ? 'Sign in' : 'Create account'}
                    </Button>
                </form>

                <div className="flex w-full items-center gap-3">
                    <Separator className="flex-1" />
                    <span className="text-xs text-muted-foreground">or</span>
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
                        ? 'Signing in...'
                        : 'Continue with Google'}
                </Button>
            </div>
        </div>
    )
}
