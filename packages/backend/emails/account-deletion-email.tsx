import { Text } from '@react-email/components'
import { render } from '@react-email/render'
import type { CSSProperties } from 'react'
import {
    bodyText,
    EmailButton,
    type EmailContent,
    EmailLayout,
    footnoteText,
    greeting,
} from './components'

const warningText: CSSProperties = {
    ...bodyText,
    margin: '12px 0 0',
    fontWeight: 600,
}

type AccountDeletionEmailProps = {
    name: string | null
    url: string
}

export const AccountDeletionEmail = ({
    name,
    url,
}: AccountDeletionEmailProps) => (
    <EmailLayout title="Eliminá tu cuenta" url={url}>
        <Text style={bodyText}>
            {greeting(name)} Recibimos un pedido para eliminar tu cuenta de
            Wallet Bot de forma permanente.
        </Text>
        <Text style={warningText}>
            Se van a borrar tu cuenta y todos tus datos: transacciones, cuentas,
            categorías, etiquetas y configuración. Esta acción no se puede
            deshacer.
        </Text>
        <EmailButton label="Eliminar mi cuenta" url={url} />
        <Text style={footnoteText}>
            Si no fuiste vos, ignorá este correo: tu cuenta no se va a
            modificar. El enlace vence en 24 horas.
        </Text>
    </EmailLayout>
)

export const accountDeletionEmail = async ({
    name,
    url,
}: AccountDeletionEmailProps): Promise<EmailContent> => {
    const email = <AccountDeletionEmail name={name} url={url} />
    return {
        subject: 'Eliminá tu cuenta — Wallet Bot',
        html: await render(email),
        text: await render(email, { plainText: true }),
    }
}
