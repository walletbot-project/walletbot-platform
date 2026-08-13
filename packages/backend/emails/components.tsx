// Shared building blocks for the transactional email templates. Spanish-only
// (es-AR), matching the web app's copy. Rendered with React Email — user
// -provided values (name) are escaped by React itself, never interpolated
// into raw HTML.
import {
    Body,
    Button,
    Container,
    Head,
    Heading,
    Html,
    Link,
    Text,
} from '@react-email/components'
import type { CSSProperties, ReactNode } from 'react'

export type EmailContent = {
    subject: string
    html: string
    text: string
}

export const greeting = (name: string | null): string =>
    name ? `¡Hola, ${name}!` : '¡Hola!'

const body: CSSProperties = {
    margin: 0,
    fontFamily: "-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif",
    color: '#1f2937',
}

const container: CSSProperties = {
    margin: '0 auto',
    maxWidth: '480px',
    padding: '32px 24px',
}

const heading: CSSProperties = {
    margin: '0 0 16px',
    fontSize: '20px',
    fontWeight: 600,
}

export const bodyText: CSSProperties = {
    margin: 0,
    fontSize: '14px',
    lineHeight: 1.6,
}

export const footnoteText: CSSProperties = {
    margin: 0,
    fontSize: '13px',
    color: '#6b7280',
    lineHeight: 1.6,
}

const fallbackText: CSSProperties = {
    margin: '24px 0 0',
    fontSize: '12px',
    color: '#6b7280',
}

const fallbackLink: CSSProperties = {
    color: '#6b7280',
    wordBreak: 'break-all',
}

const buttonWrapper: CSSProperties = {
    margin: '24px 0',
}

const button: CSSProperties = {
    display: 'inline-block',
    padding: '12px 24px',
    borderRadius: '8px',
    background: '#1f2937',
    color: '#ffffff',
    textDecoration: 'none',
    fontWeight: 600,
}

type EmailLayoutProps = {
    title: string
    url: string
    children: ReactNode
}

export const EmailLayout = ({ title, url, children }: EmailLayoutProps) => (
    <Html lang="es">
        <Head />
        <Body style={body}>
            <Container style={container}>
                <Heading as="h1" style={heading}>
                    {title}
                </Heading>
                {children}
                <Text style={fallbackText}>
                    Si el botón no funciona, copiá y pegá este enlace en tu
                    navegador:
                    <br />
                    <Link href={url} style={fallbackLink}>
                        {url}
                    </Link>
                </Text>
            </Container>
        </Body>
    </Html>
)

type EmailButtonProps = {
    label: string
    url: string
}

export const EmailButton = ({ label, url }: EmailButtonProps) => (
    <Text style={buttonWrapper}>
        <Button href={url} style={button}>
            {label}
        </Button>
    </Text>
)
