import { useState } from 'react'
import { useLocation } from 'react-router-dom'

import googleIcon from '@/assets/google.svg'
import { Button } from '@/components/ui/button'
import { authClient } from '@/lib/auth-client'

export function Login() {
    const location = useLocation()
    const from = location.state?.from?.pathname || '/'

    const [loading, setLoading] = useState(false)

    const handleGoogleSignIn = () => {
        setLoading(true)
        authClient.signIn.social({
            provider: 'google',
            callbackURL: window.location.origin + from,
        })
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

                <Button
                    variant="outline"
                    className="w-full"
                    onClick={handleGoogleSignIn}
                    disabled={loading}
                >
                    {loading ? (
                        <svg
                            className="h-5 w-5 animate-spin"
                            viewBox="0 0 24 24"
                            fill="none"
                            role="img"
                            aria-label="Loading"
                        >
                            <circle
                                className="opacity-25"
                                cx="12"
                                cy="12"
                                r="10"
                                stroke="currentColor"
                                strokeWidth="4"
                            />
                            <path
                                className="opacity-75"
                                fill="currentColor"
                                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                            />
                        </svg>
                    ) : (
                        <img
                            src={googleIcon}
                            alt="Google"
                            className="h-5 w-5"
                        />
                    )}
                    {loading ? 'Signing in...' : 'Continue with Google'}
                </Button>
            </div>
        </div>
    )
}
