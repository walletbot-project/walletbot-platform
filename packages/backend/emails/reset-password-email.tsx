import { Text } from '@react-email/components'
import { render } from '@react-email/render'
import {
    bodyText,
    EmailButton,
    type EmailContent,
    EmailLayout,
    footnoteText,
    greeting,
} from './components'

type ResetPasswordEmailProps = {
    name: string | null
    url: string
}

export const ResetPasswordEmail = ({ name, url }: ResetPasswordEmailProps) => (
    <EmailLayout title="Restablecé tu contraseña" url={url}>
        <Text style={bodyText}>
            {greeting(name)} Recibimos un pedido para restablecer tu contraseña.
        </Text>
        <EmailButton label="Restablecer contraseña" url={url} />
        <Text style={footnoteText}>
            Si no fuiste vos, ignorá este correo: tu contraseña no va a cambiar.
            El enlace vence en 1 hora.
        </Text>
    </EmailLayout>
)

export const resetPasswordEmail = async ({
    name,
    url,
}: ResetPasswordEmailProps): Promise<EmailContent> => {
    const email = <ResetPasswordEmail name={name} url={url} />
    return {
        subject: 'Restablecé tu contraseña — Wallet Bot',
        html: await render(email),
        text: await render(email, { plainText: true }),
    }
}
