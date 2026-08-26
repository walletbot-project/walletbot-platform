import type { Locale } from '@wallet-bot/shared'

/**
 * Copy for the transactional emails, in every locale the product ships.
 *
 * This is a THIRD message catalog, next to the native ARB files and the web
 * app's `useT`. It exists because neither of those reaches the server: these
 * strings are rendered inside a Convex Node action, with no Flutter
 * `AppLocalizations` and no React context. Which locale a send uses is decided
 * by `resolveOutboundLocale` (convex/emails/helpers.ts) from the recipient's
 * `userSettings.language`.
 *
 * The Spanish entries are the copy these templates shipped with, moved here
 * verbatim.
 */
export type EmailMessages = {
    greeting: (name: string | null) => string
    linkFallback: string
    verification: {
        subject: string
        title: string
        body: string
        button: string
        footnote: string
    }
    resetPassword: {
        subject: string
        title: string
        body: string
        button: string
        footnote: string
    }
    accountDeletion: {
        subject: string
        title: string
        body: string
        warning: string
        button: string
        footnote: string
    }
}

const es: EmailMessages = {
    greeting: (name) => (name ? `¡Hola, ${name}!` : '¡Hola!'),
    linkFallback:
        'Si el botón no funciona, copiá y pegá este enlace en tu navegador:',
    verification: {
        subject: 'Verificá tu correo — Wallet Bot',
        title: 'Verificá tu correo',
        body: 'Confirmá tu dirección de correo para empezar a usar Wallet Bot.',
        button: 'Verificar correo',
        footnote:
            'Si no creaste una cuenta en Wallet Bot, ignorá este correo. El enlace vence en 24 horas.',
    },
    resetPassword: {
        subject: 'Restablecé tu contraseña — Wallet Bot',
        title: 'Restablecé tu contraseña',
        body: 'Recibimos un pedido para restablecer tu contraseña.',
        button: 'Restablecer contraseña',
        footnote:
            'Si no fuiste vos, ignorá este correo: tu contraseña no va a cambiar. El enlace vence en 1 hora.',
    },
    accountDeletion: {
        subject: 'Eliminá tu cuenta — Wallet Bot',
        title: 'Eliminá tu cuenta',
        body: 'Recibimos un pedido para eliminar tu cuenta de Wallet Bot de forma permanente.',
        warning:
            'Se van a borrar tu cuenta y todos tus datos: transacciones, cuentas, categorías, etiquetas y configuración. Esta acción no se puede deshacer.',
        button: 'Eliminar mi cuenta',
        footnote:
            'Si no fuiste vos, ignorá este correo: tu cuenta no se va a modificar. El enlace vence en 24 horas.',
    },
}

const en: EmailMessages = {
    greeting: (name) => (name ? `Hi ${name}!` : 'Hi!'),
    linkFallback:
        "If the button doesn't work, copy and paste this link into your browser:",
    verification: {
        subject: 'Verify your email — Wallet Bot',
        title: 'Verify your email',
        body: 'Confirm your email address to start using Wallet Bot.',
        button: 'Verify email',
        footnote:
            "If you didn't create a Wallet Bot account, ignore this email. The link expires in 24 hours.",
    },
    resetPassword: {
        subject: 'Reset your password — Wallet Bot',
        title: 'Reset your password',
        body: 'We received a request to reset your password.',
        button: 'Reset password',
        footnote:
            "If this wasn't you, ignore this email: your password won't change. The link expires in 1 hour.",
    },
    accountDeletion: {
        subject: 'Delete your account — Wallet Bot',
        title: 'Delete your account',
        body: 'We received a request to permanently delete your Wallet Bot account.',
        warning:
            'Your account and all your data will be erased: transactions, accounts, categories, tags and settings. This cannot be undone.',
        button: 'Delete my account',
        footnote:
            "If this wasn't you, ignore this email: your account won't be modified. The link expires in 24 hours.",
    },
}

export const EMAIL_MESSAGES: Record<Locale, EmailMessages> = { es, en }
