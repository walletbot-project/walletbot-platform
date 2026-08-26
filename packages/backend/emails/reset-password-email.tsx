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

export const ResetPasswordEmail = ({ name, url, locale }: EmailProps) => {
    const t = EMAIL_MESSAGES[locale]
    return (
        <EmailLayout title={t.resetPassword.title} url={url} locale={locale}>
            <Text style={bodyText}>
                {t.greeting(name)} {t.resetPassword.body}
            </Text>
            <EmailButton label={t.resetPassword.button} url={url} />
            <Text style={footnoteText}>{t.resetPassword.footnote}</Text>
        </EmailLayout>
    )
}

export const resetPasswordEmail = async ({
    name,
    url,
    locale,
}: EmailProps): Promise<EmailContent> => {
    const email = <ResetPasswordEmail name={name} url={url} locale={locale} />
    return {
        subject: EMAIL_MESSAGES[locale].resetPassword.subject,
        html: await render(email),
        text: await render(email, { plainText: true }),
    }
}
