'use node'

import { v } from 'convex/values'
import { resetPasswordEmail } from '../../emails/reset-password-email'
import { verificationEmail } from '../../emails/verification-email'
import { internalAction } from '../_generated/server'
import { resend } from './helpers'

// React Email renders through react-dom/server, which the default Convex
// runtime doesn't support — the @convex-dev/resend docs require a Node
// action for it. These actions render the template and enqueue the email;
// delivery itself stays durable inside the resend component.

const FROM = process.env.EMAIL_FROM ?? 'Wallet Bot <no-reply@walletbot.live>'

const sendArgs = {
    to: v.string(),
    name: v.union(v.string(), v.null()),
    url: v.string(),
}

export const sendVerificationEmail = internalAction({
    args: sendArgs,
    handler: async (ctx, { to, name, url }) => {
        const { subject, html, text } = await verificationEmail({ name, url })
        await resend.sendEmail(ctx, { from: FROM, to, subject, html, text })
        return null
    },
})

export const sendResetPasswordEmail = internalAction({
    args: sendArgs,
    handler: async (ctx, { to, name, url }) => {
        const { subject, html, text } = await resetPasswordEmail({ name, url })
        await resend.sendEmail(ctx, { from: FROM, to, subject, html, text })
        return null
    },
})
