// Private email templates for the emails feature. Spanish-only (es-AR),
// matching the web app's copy. Plain inline-styled HTML + text fallback —
// no template engine, no extra deps.

type TemplateArgs = {
    name: string | null
    url: string
}

export type EmailContent = {
    subject: string
    html: string
    text: string
}

// User-provided values (name) are interpolated into HTML — always escape.
const escapeHtml = (value: string): string =>
    value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;')

const layout = (title: string, bodyHtml: string, url: string): string => `
<div style="margin:0 auto;max-width:480px;padding:32px 24px;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1f2937;">
    <h1 style="margin:0 0 16px;font-size:20px;font-weight:600;">${title}</h1>
    ${bodyHtml}
    <p style="margin:24px 0 0;font-size:12px;color:#6b7280;">
        Si el botón no funciona, copiá y pegá este enlace en tu navegador:<br />
        <a href="${url}" style="color:#6b7280;word-break:break-all;">${url}</a>
    </p>
</div>`

const button = (label: string, url: string): string =>
    `<p style="margin:24px 0;"><a href="${url}" style="display:inline-block;padding:12px 24px;border-radius:8px;background:#1f2937;color:#ffffff;text-decoration:none;font-weight:600;">${label}</a></p>`

const greeting = (name: string | null): string =>
    name ? `¡Hola, ${escapeHtml(name)}!` : '¡Hola!'

export const verificationEmail = ({
    name,
    url,
}: TemplateArgs): EmailContent => {
    const subject = 'Verificá tu correo — Wallet Bot'
    const html = layout(
        'Verificá tu correo',
        `<p style="margin:0;font-size:14px;line-height:1.6;">
            ${greeting(name)} Confirmá tu dirección de correo para empezar a usar Wallet Bot.
        </p>
        ${button('Verificar correo', url)}
        <p style="margin:0;font-size:13px;color:#6b7280;line-height:1.6;">
            Si no creaste una cuenta en Wallet Bot, ignorá este correo.
            El enlace vence en 24 horas.
        </p>`,
        url,
    )
    const text = [
        `${greeting(name).replaceAll('¡', '').replaceAll('!', '')}.`,
        'Confirmá tu dirección de correo para empezar a usar Wallet Bot:',
        url,
        '',
        'Si no creaste una cuenta en Wallet Bot, ignorá este correo. El enlace vence en 24 horas.',
    ].join('\n')
    return { subject, html, text }
}

export const resetPasswordEmail = ({
    name,
    url,
}: TemplateArgs): EmailContent => {
    const subject = 'Restablecé tu contraseña — Wallet Bot'
    const html = layout(
        'Restablecé tu contraseña',
        `<p style="margin:0;font-size:14px;line-height:1.6;">
            ${greeting(name)} Recibimos un pedido para restablecer tu contraseña.
        </p>
        ${button('Restablecer contraseña', url)}
        <p style="margin:0;font-size:13px;color:#6b7280;line-height:1.6;">
            Si no fuiste vos, ignorá este correo: tu contraseña no va a cambiar.
            El enlace vence en 1 hora.
        </p>`,
        url,
    )
    const text = [
        `${greeting(name).replaceAll('¡', '').replaceAll('!', '')}.`,
        'Recibimos un pedido para restablecer tu contraseña. Abrí este enlace:',
        url,
        '',
        'Si no fuiste vos, ignorá este correo: tu contraseña no va a cambiar. El enlace vence en 1 hora.',
    ].join('\n')
    return { subject, html, text }
}
