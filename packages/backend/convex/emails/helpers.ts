import { isActionCtx, type RunMutationCtx } from '@convex-dev/better-auth/utils'
import { Resend } from '@convex-dev/resend'
import type { FunctionReference } from 'convex/server'
import { components, internal } from '../_generated/api'
import type { DataModel } from '../_generated/dataModel'

// testMode is hardcoded OFF: every deployment sends real emails to real
// addresses. (With testMode on, sendEmail throws for any recipient that
// isn't a resend.dev test address.) Note this contradicts the
// RESEND_TEST_MODE mitigation described in docs/riesgos.md R-011 — that env
// var is not read anywhere.
export const resend: Resend = new Resend(components.resend, {
    testMode: false,
    onEmailEvent: internal.emails.internal.handleEmailEvent,
})

type SendArgs = {
    to: string
    name: string | null
    url: string
}

type SendEmailAction = FunctionReference<'action', 'internal', SendArgs, null>

// Rendering the React Email templates requires the Node runtime, so sending
// lives in emails/nodeActions.ts. From an action ctx (every better-auth HTTP
// flow) call it directly so render/enqueue failures still propagate to the
// caller as errors (authNative's emailSendFailedResponse depends on that).
// A mutation ctx can't cross runtimes synchronously — schedule instead; the
// enqueue then commits with the transaction but failures only surface in logs.
const runSendEmailAction = async (
    ctx: RunMutationCtx<DataModel>,
    action: SendEmailAction,
    args: SendArgs,
): Promise<void> => {
    if (isActionCtx(ctx)) {
        await ctx.runAction(action, args)
        return
    }
    await ctx.scheduler.runAfter(0, action, args)
}

export const sendVerificationEmail = async (
    ctx: RunMutationCtx<DataModel>,
    args: SendArgs,
): Promise<void> => {
    await runSendEmailAction(
        ctx,
        internal.emails.nodeActions.sendVerificationEmail,
        args,
    )
}

export const sendResetPasswordEmail = async (
    ctx: RunMutationCtx<DataModel>,
    args: SendArgs,
): Promise<void> => {
    await runSendEmailAction(
        ctx,
        internal.emails.nodeActions.sendResetPasswordEmail,
        args,
    )
}
