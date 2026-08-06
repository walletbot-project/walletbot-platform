import { LoaderCircle, Mail, MailCheck, TriangleAlert } from 'lucide-react'
import { type FormEvent, useState } from 'react'
import { Link } from 'react-router-dom'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useCachedSession } from '@/hooks/use-cached-session'

// Guard-free page (see router.tsx): works logged in (reached from the
// account menu, email prefilled) and logged out (Play's data-deletion policy
// requires a web-accessible deletion URL). The endpoint never discloses
// whether the email exists.
export function DeleteAccount() {
    const { session } = useCachedSession()
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
            const res = await fetch(
                `${import.meta.env.VITE_CONVEX_SITE_URL}/v1/account-deletion/request`,
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email }),
                },
            )
            if (!res.ok) {
                const body = (await res.json().catch(() => null)) as {
                    message?: string
                } | null
                throw new Error(body?.message ?? 'No se pudo enviar el correo')
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
                        Eliminar tu cuenta
                    </h1>
                    <p className="text-sm text-muted-foreground">
                        {sentTo
                            ? `Si existe una cuenta para ${sentTo}, le enviamos un enlace para eliminarla.`
                            : 'Ingresá tu correo y te enviamos un enlace para confirmar la eliminación.'}
                    </p>
                </div>

                {sentTo ? (
                    <div className="flex w-full flex-col items-center gap-4">
                        <div className="rounded-full bg-muted p-4">
                            <MailCheck className="size-6 text-muted-foreground" />
                        </div>
                        <p className="text-center text-sm text-muted-foreground">
                            Revisá tu bandeja de entrada. El enlace vence en 24
                            horas.
                        </p>
                        <Button
                            variant="outline"
                            className="w-full"
                            render={<Link to="/" />}
                        >
                            Volver al inicio
                        </Button>
                    </div>
                ) : (
                    <form
                        className="flex w-full flex-col gap-4"
                        onSubmit={handleSubmit}
                    >
                        <div className="flex items-start gap-3 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2.5">
                            <TriangleAlert className="mt-0.5 size-4 shrink-0 text-destructive" />
                            <p className="text-sm text-destructive">
                                Se van a borrar tu cuenta y todos tus datos de
                                forma permanente. Esta acción no se puede
                                deshacer.
                            </p>
                        </div>

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
                                    defaultValue={session?.user.email}
                                    required
                                    disabled={loading}
                                />
                            </div>
                        </div>

                        <Button
                            type="submit"
                            variant="destructive"
                            className="w-full"
                            disabled={loading}
                        >
                            {loading ? (
                                <LoaderCircle className="animate-spin" />
                            ) : null}
                            Enviar enlace de eliminación
                        </Button>

                        <Button
                            variant="ghost"
                            className="w-full"
                            render={<Link to="/" />}
                        >
                            Cancelar
                        </Button>
                    </form>
                )}
            </div>
        </div>
    )
}
