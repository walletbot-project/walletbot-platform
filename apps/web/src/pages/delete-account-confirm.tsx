import {
    CircleAlert,
    CircleCheck,
    LoaderCircle,
    TriangleAlert,
} from 'lucide-react'
import { type FormEvent, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { authClient } from '@/lib/auth-client'

const CONFIRM_WORD = 'ELIMINAR'

// Landing page for the emailed deletion link. Guard-free (see router.tsx):
// the link can be opened with or without a session. Possession of the token
// is the authorization — confirming here is final and irreversible.
export function DeleteAccountConfirm() {
    const [searchParams] = useSearchParams()
    const token = searchParams.get('token')

    const [confirmWord, setConfirmWord] = useState('')
    const [loading, setLoading] = useState(false)
    const [done, setDone] = useState(false)
    // The token is single-use: if the submit fails with invalid_token the
    // link is dead even though it's still in the URL.
    const [tokenSpent, setTokenSpent] = useState(false)

    const invalidLink = !token || tokenSpent

    const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault()
        if (!token || confirmWord !== CONFIRM_WORD) return

        setLoading(true)
        try {
            const res = await fetch(
                `${import.meta.env.VITE_CONVEX_SITE_URL}/v1/account-deletion/confirm`,
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ token }),
                },
            )
            if (res.status === 400) {
                setTokenSpent(true)
                return
            }
            if (!res.ok) {
                throw new Error('No se pudo eliminar la cuenta')
            }

            setDone(true)
            toast.success('Tu cuenta fue eliminada')
            // Clear any local session state — the server already revoked
            // every session, so this can only fail harmlessly.
            try {
                await authClient.signOut()
            } catch {
                // The account no longer exists; a failed sign-out is expected.
            }
        } catch (err) {
            toast.error(
                err instanceof Error
                    ? err.message
                    : 'No se pudo eliminar la cuenta',
            )
        } finally {
            setLoading(false)
        }
    }

    if (done) {
        return (
            <div className="flex min-h-screen items-center justify-center bg-background">
                <div className="flex w-full max-w-sm flex-col items-center gap-6 px-4 text-center">
                    <div className="rounded-full bg-muted p-4">
                        <CircleCheck className="size-6 text-muted-foreground" />
                    </div>
                    <div className="flex flex-col gap-2">
                        <h1 className="text-2xl font-semibold tracking-tight">
                            Tu cuenta fue eliminada
                        </h1>
                        <p className="text-sm text-muted-foreground">
                            Estamos borrando todos tus datos de forma
                            permanente. Gracias por haber usado Wallet Bot.
                        </p>
                    </div>
                </div>
            </div>
        )
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
                            El enlace no es válido, ya venció o ya fue usado. Si
                            todavía querés eliminar tu cuenta, pedí un enlace
                            nuevo.
                        </p>
                    </div>
                    <Button
                        className="w-full"
                        render={<Link to="/delete-account" />}
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
                    <div className="rounded-full bg-destructive/10 p-4">
                        <TriangleAlert className="size-6 text-destructive" />
                    </div>
                    <h1 className="text-2xl font-semibold tracking-tight">
                        ¿Eliminar tu cuenta definitivamente?
                    </h1>
                    <p className="text-sm text-muted-foreground">
                        Esta acción es permanente y no se puede deshacer.
                    </p>
                </div>

                <div className="w-full rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-3">
                    <p className="text-sm font-medium text-destructive">
                        Se va a borrar para siempre:
                    </p>
                    <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-destructive">
                        <li>Todas tus transacciones</li>
                        <li>Tus cuentas y saldos</li>
                        <li>Categorías, etiquetas y configuración</li>
                        <li>Tu usuario y acceso a Wallet Bot</li>
                    </ul>
                </div>

                <form
                    className="flex w-full flex-col gap-4"
                    onSubmit={handleSubmit}
                >
                    <div className="grid gap-2">
                        <Label htmlFor="confirm-word">
                            Para confirmar, escribí{' '}
                            <span className="font-semibold">
                                {CONFIRM_WORD}
                            </span>
                        </Label>
                        <Input
                            id="confirm-word"
                            name="confirm-word"
                            autoComplete="off"
                            placeholder={CONFIRM_WORD}
                            value={confirmWord}
                            onChange={(e) => setConfirmWord(e.target.value)}
                            required
                            disabled={loading}
                        />
                    </div>

                    <Button
                        type="submit"
                        variant="destructive"
                        className="w-full"
                        disabled={loading || confirmWord !== CONFIRM_WORD}
                    >
                        {loading ? (
                            <LoaderCircle className="animate-spin" />
                        ) : null}
                        Eliminar mi cuenta definitivamente
                    </Button>

                    <Button
                        variant="ghost"
                        className="w-full"
                        render={<Link to="/" />}
                    >
                        Cancelar
                    </Button>
                </form>
            </div>
        </div>
    )
}
