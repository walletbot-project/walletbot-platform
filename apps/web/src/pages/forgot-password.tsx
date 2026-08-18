import { LoaderCircle, Mail, MailCheck } from 'lucide-react'
import { type FormEvent, useState } from 'react'
import { Link } from 'react-router-dom'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { authClient } from '@/lib/auth-client'

export function ForgotPassword() {
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
            // No redirectTo: the backend canonicalizes the link to land on
            // /reset-password. The endpoint never discloses whether the email
            // exists, so any non-error response flips to the sent state.
            const result = await authClient.requestPasswordReset({ email })
            if (result.error) {
                throw new Error(
                    result.error.message ?? 'No se pudo enviar el correo',
                )
            }
            setSentTo(email)
        } catch (err) {
            toast.error(
                err instanceof Error
                    ? err.message
                    : 'No se pudo enviar el correo',
            )
        } finally {
            setLoading(false)
        }
    }

    return (
        <div className="flex min-h-screen items-center justify-center bg-background">
            <div className="flex w-full max-w-sm flex-col items-center gap-6 px-4">
                <div className="flex flex-col items-center gap-2 text-center">
                    <h1 className="text-2xl font-semibold tracking-tight">
                        Restablecer contraseña
                    </h1>
                    <p className="text-sm text-muted-foreground">
                        {sentTo
                            ? `Si existe una cuenta para ${sentTo}, le enviamos un enlace para restablecer la contraseña.`
                            : 'Ingresá tu correo y te enviamos un enlace para restablecerla.'}
                    </p>
                </div>

                {sentTo ? (
                    <div className="flex w-full flex-col items-center gap-4">
                        <div className="rounded-full bg-muted p-4">
                            <MailCheck className="size-6 text-muted-foreground" />
                        </div>
                        <p className="text-center text-sm text-muted-foreground">
                            Revisá tu bandeja de entrada. El enlace vence en 1
                            hora.
                        </p>
                        <Button
                            variant="outline"
                            className="w-full"
                            render={<Link to="/login" />}
                        >
                            Volver a iniciar sesión
                        </Button>
                    </div>
                ) : (
                    <form
                        className="flex w-full flex-col gap-4"
                        onSubmit={handleSubmit}
                    >
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
                                    disabled={loading}
                                />
                            </div>
                        </div>

                        <Button
                            type="submit"
                            className="w-full"
                            disabled={loading}
                        >
                            {loading ? (
                                <LoaderCircle className="animate-spin" />
                            ) : null}
                            Enviar enlace
                        </Button>

                        <Button
                            variant="ghost"
                            className="w-full"
                            render={<Link to="/login" />}
                        >
                            Volver a iniciar sesión
                        </Button>
                    </form>
                )}
            </div>
        </div>
    )
}
