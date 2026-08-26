import { Text } from '@react-email/components'
import { render } from '@react-email/render'
import {
    bodyText,
    EmailButton,
    type EmailContent,
    EmailLayout,
    type EmailProps,
    footnoteText,
} from './components'
import { EMAIL_MESSAGES } from './messages'

export const VerificationEmail = ({ name, url, locale }: EmailProps) => {
    const t = EMAIL_MESSAGES[locale]
    return (
        <EmailLayout title={t.verification.title} url={url} locale={locale}>
            <Text style={bodyText}>
                {t.greeting(name)} {t.verification.body}
            </Text>
            <EmailButton label={t.verification.button} url={url} />
            <Text style={footnoteText}>{t.verification.footnote}</Text>
        </EmailLayout>
    )
}

export const verificationEmail = async ({
    name,
    url,
    locale,
}: EmailProps): Promise<EmailContent> => {
    const email = <VerificationEmail name={name} url={url} locale={locale} />
    return {
        subject: EMAIL_MESSAGES[locale].verification.subject,
        html: await render(email),
        text: await render(email, { plainText: true }),
    }
}
