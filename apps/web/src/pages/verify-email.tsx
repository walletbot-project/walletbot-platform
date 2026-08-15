import { Link, useSearchParams } from 'react-router-dom'
import { Icon } from '@/components/m3/icon'

import { Button } from '@/components/ui/button'

type VerifyState = {
    icon: 'success' | 'error'
    title: string
    description: string
}

const stateForError = (error: string | null): VerifyState => {
    if (error === null) {
        return {
            icon: 'success',
            title: '¡Listo! Tu correo fue verificado',
            description: 'Ya podés iniciar sesión con tu cuenta.',
        }
    }
    if (error === 'TOKEN_EXPIRED') {
        return {
            icon: 'error',
            title: 'El enlace venció',
            description:
                'Iniciá sesión y te enviamos un enlace nuevo automáticamente.',
        }
    }
    // INVALID_TOKEN, USER_NOT_FOUND, INVALID_USER, or anything unexpected.
    return {
        icon: 'error',
        title: 'No pudimos verificar tu correo',
        description:
            'El enlace no es válido. Volvé a iniciar sesión para recibir un enlace nuevo.',
    }
}

export function VerifyEmail() {
    const [searchParams] = useSearchParams()
    const state = stateForError(searchParams.get('error'))

    return (
        <div className="flex min-h-dvh items-center justify-center bg-surface px-5 py-6">
            <div className="flex w-full max-w-sm flex-col items-center gap-6 px-4 text-center">
                {state.icon === 'success' ? (
                    <div className="rounded-full bg-surface-container-highest p-4">
                        <Icon
                            name="mark_email_read"
                            filled
                            size={24}
                            className="text-on-surface-variant"
                        />
                    </div>
                ) : (
                    <div className="rounded-full bg-destructive/10 p-4">
                        <Icon
                            name="error"
                            filled
                            size={24}
                            className="text-error"
                        />
                    </div>
                )}
                <div className="flex flex-col gap-2">
                    <h1 className="m3-headline-small font-semibold">
                        {state.title}
                    </h1>
                    <p className="m3-body-medium text-on-surface-variant">
                        {state.description}
                    </p>
                </div>
                <Button
                    className="w-full"
                    nativeButton={false}
                    render={<Link to="/login" />}
                >
                    Iniciar sesión
                </Button>
            </div>
        </div>
    )
}
