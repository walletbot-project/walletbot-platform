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

type VerificationEmailProps = {
    name: string | null
    url: string
}

export const VerificationEmail = ({ name, url }: VerificationEmailProps) => (
    <EmailLayout title="Verificá tu correo" url={url}>
        <Text style={bodyText}>
            {greeting(name)} Confirmá tu dirección de correo para empezar a usar
            Wallet Bot.
        </Text>
        <EmailButton label="Verificar correo" url={url} />
        <Text style={footnoteText}>
            Si no creaste una cuenta en Wallet Bot, ignorá este correo. El
            enlace vence en 24 horas.
        </Text>
    </EmailLayout>
)

export const verificationEmail = async ({
    name,
    url,
}: VerificationEmailProps): Promise<EmailContent> => {
    const email = <VerificationEmail name={name} url={url} />
    return {
        subject: 'Verificá tu correo — Wallet Bot',
        html: await render(email),
        text: await render(email, { plainText: true }),
    }
}
