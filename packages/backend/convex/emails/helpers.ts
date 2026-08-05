import type { RunMutationCtx } from '@convex-dev/better-auth/utils'
import { Resend } from '@convex-dev/resend'
import { components, internal } from '../_generated/api'
import type { DataModel } from '../_generated/dataModel'
import { resetPasswordEmail, verificationEmail } from './utils'

// testMode is hardcoded OFF: every deployment sends real emails to real
// addresses. (With testMode on, sendEmail throws for any recipient that
// isn't a resend.dev test address.) Note this contradicts the
// RESEND_TEST_MODE mitigation described in docs/riesgos.md R-011 — that env
// var is not read anywhere.
export const resend: Resend = new Resend(components.resend, {
    testMode: false,
    onEmailEvent: internal.emails.internal.handleEmailEvent,
})

const FROM = process.env.EMAIL_FROM ?? 'Wallet Bot <no-reply@walletbot.live>'

type SendArgs = {
    to: string
    name: string | null
    url: string
}

export const sendVerificationEmail = async (
    ctx: RunMutationCtx<DataModel>,
    { to, name, url }: SendArgs,
): Promise<void> => {
    const { subject, html, text } = verificationEmail({ name, url })
    await resend.sendEmail(ctx, { from: FROM, to, subject, html, text })
}

export const sendResetPasswordEmail = async (
    ctx: RunMutationCtx<DataModel>,
    { to, name, url }: SendArgs,
): Promise<void> => {
    const { subject, html, text } = resetPasswordEmail({ name, url })
    await resend.sendEmail(ctx, { from: FROM, to, subject, html, text })
}
