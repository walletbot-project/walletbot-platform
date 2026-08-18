import { CircleAlert, LoaderCircle, Lock } from 'lucide-react'
import { type FormEvent, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { authClient } from '@/lib/auth-client'

export function ResetPassword() {
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
            setError('Las contraseñas no coinciden')
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
                    result.error.message ??
                        'No se pudo restablecer la contraseña',
                )
            }
            toast.success(
                'Contraseña actualizada. Iniciá sesión con tu nueva contraseña.',
            )
            navigate('/login', { replace: true })
        } catch (err) {
            setError(
                err instanceof Error
                    ? err.message
                    : 'No se pudo restablecer la contraseña',
            )
        } finally {
            setLoading(false)
        }
    }

    if (invalidLink) {
        return (
            <div className="flex min-h-screen items-center justify-center bg-background">
                <div className="flex w-full max-w-sm flex-col items-center gap-6 px-4 text-center">
                    <div className="rounded-full bg-destructive/10 p-4">
                        <CircleAlert className="size-6 text-destructive" />
                    </div>
                    <div className="flex flex-col gap-2">
                        <h1 className="text-2xl font-semibold tracking-tight">
                            Enlace no válido
                        </h1>
                        <p className="text-sm text-muted-foreground">
                            El enlace no es válido o ya venció. Pedí uno nuevo
                            para restablecer tu contraseña.
                        </p>
                    </div>
                    <Button
                        className="w-full"
                        render={<Link to="/forgot-password" />}
                    >
                        Pedir un enlace nuevo
                    </Button>
                </div>
            </div>
        )
    }

    return (
        <div className="flex min-h-screen items-center justify-center bg-background">
            <div className="flex w-full max-w-sm flex-col items-center gap-6 px-4">
                <div className="flex flex-col items-center gap-2 text-center">
                    <h1 className="text-2xl font-semibold tracking-tight">
                        Nueva contraseña
                    </h1>
                    <p className="text-sm text-muted-foreground">
                        Elegí una contraseña nueva para tu cuenta.
                    </p>
                </div>

                <form
                    className="flex w-full flex-col gap-4"
                    onSubmit={handleSubmit}
                >
                    <div className="grid gap-2">
                        <Label htmlFor="password">Nueva contraseña</Label>
                        <div className="relative">
                            <Lock className="-translate-y-1/2 pointer-events-none absolute top-1/2 left-2.5 size-4 text-muted-foreground" />
                            <Input
                                id="password"
                                name="password"
                                type="password"
                                autoComplete="new-password"
                                placeholder="Al menos 8 caracteres"
                                className="pl-8"
                                minLength={8}
                                required
                                disabled={loading}
                            />
                        </div>
                    </div>

                    <div className="grid gap-2">
                        <Label htmlFor="confirm">Repetir contraseña</Label>
                        <div className="relative">
                            <Lock className="-translate-y-1/2 pointer-events-none absolute top-1/2 left-2.5 size-4 text-muted-foreground" />
                            <Input
                                id="confirm"
                                name="confirm"
                                type="password"
                                autoComplete="new-password"
                                placeholder="La misma contraseña"
                                className="pl-8"
                                minLength={8}
                                required
                                disabled={loading}
                            />
                        </div>
                    </div>

                    {error ? (
                        <p className="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                            {error}
                        </p>
                    ) : null}

                    <Button type="submit" className="w-full" disabled={loading}>
                        {loading ? (
                            <LoaderCircle className="animate-spin" />
                        ) : null}
                        Restablecer contraseña
                    </Button>
                </form>
            </div>
        </div>
    )
}
