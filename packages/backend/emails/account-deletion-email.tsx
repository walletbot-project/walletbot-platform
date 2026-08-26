import { Text } from '@react-email/components'
import { render } from '@react-email/render'
import type { CSSProperties } from 'react'
import {
    bodyText,
    EmailButton,
    type EmailContent,
    EmailLayout,
    type EmailProps,
    footnoteText,
} from './components'
import { EMAIL_MESSAGES } from './messages'

const warningText: CSSProperties = {
    ...bodyText,
    margin: '12px 0 0',
    fontWeight: 600,
}

export const AccountDeletionEmail = ({ name, url, locale }: EmailProps) => {
    const t = EMAIL_MESSAGES[locale]
    return (
        <EmailLayout title={t.accountDeletion.title} url={url} locale={locale}>
            <Text style={bodyText}>
                {t.greeting(name)} {t.accountDeletion.body}
            </Text>
            <Text style={warningText}>{t.accountDeletion.warning}</Text>
            <EmailButton label={t.accountDeletion.button} url={url} />
            <Text style={footnoteText}>{t.accountDeletion.footnote}</Text>
        </EmailLayout>
    )
}

export const accountDeletionEmail = async ({
    name,
    url,
    locale,
}: EmailProps): Promise<EmailContent> => {
    const email = <AccountDeletionEmail name={name} url={url} locale={locale} />
    return {
        subject: EMAIL_MESSAGES[locale].accountDeletion.subject,
        html: await render(email),
        text: await render(email, { plainText: true }),
    }
}
