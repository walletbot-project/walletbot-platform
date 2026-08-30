import { v } from 'convex/values'
import { internal } from '../_generated/api'
import type { Id } from '../_generated/dataModel'
import { type ActionCtx, internalAction } from '../_generated/server'
import { supportEmailAttachment } from '../schema/supportEmails'
import {
    capBodies,
    errorMessage,
    getForwardFrom,
    getForwardTo,
    getResendClient,
    isForwardLoop,
} from './utils'

type ForwardOutcome = {
    status: 'sent' | 'skipped' | 'failed'
    forwardTo: string | null
    forwardResendEmailId: string | null
    forwardError: string | null
}

/**
 * Redirects one archived email to the configured destination.
 *
 * Uses Resend's own forwarding helper, which re-sends the stored message
 * (body and attachments included) without this backend ever handling the
 * bytes — `passthrough` defaults to true, so the recipient gets the original
 * message rather than a wrapper
 * (resend.com/docs/dashboard/receiving/forward-emails).
 */
const forwardEmail = async (
    resendEmailId: string,
    from: string,
): Promise<ForwardOutcome> => {
    const forwardTo = getForwardTo()
    if (forwardTo === null) {
        console.warn(
            `support email ${resendEmailId} archived but not forwarded: SUPPORT_FORWARD_TO is not set`,
        )
        return {
            status: 'skipped',
            forwardTo: null,
            forwardResendEmailId: null,
            forwardError: null,
        }
    }

    if (isForwardLoop(from, forwardTo)) {
        console.warn(
            `support email ${resendEmailId} not forwarded: sender ${from} would create a mail loop`,
        )
        return {
            status: 'skipped',
            forwardTo,
            forwardResendEmailId: null,
            forwardError: null,
        }
    }

    const result = await getResendClient()
        .emails.receiving.forward({
            emailId: resendEmailId,
            to: forwardTo,
            from: getForwardFrom(),
        })
        .catch((error: unknown) => ({
            data: null,
            error: { message: errorMessage(error) },
        }))

    if (result.error !== null || result.data === null) {
        const message = result.error?.message ?? 'unknown error'
        console.error(
            `support email ${resendEmailId} failed to forward to ${forwardTo}: ${message}`,
        )
        return {
            status: 'failed',
            forwardTo,
            forwardResendEmailId: null,
            forwardError: message,
        }
    }

    return {
        status: 'sent',
        forwardTo,
        forwardResendEmailId: result.data.id,
        forwardError: null,
    }
}

/**
 * Archive-then-forward for one inbound support email.
 *
 * Runs as a scheduled action rather than inside the webhook handler so Resend
 * gets its 2xx immediately: the `email.received` webhook carries metadata only,
 * and both the content fetch and the forward are extra round trips to Resend's
 * API.
 *
 * Ordering is deliberate — archive first, forward second. The database row is
 * the durable record; a forward that fails leaves a `failed` row someone can
 * act on, whereas forwarding first and crashing before the insert would drop
 * the email entirely.
 */
export const processInboundEmail = internalAction({
    args: {
        resendEmailId: v.string(),
        receivedAt: v.number(),
        // Webhook metadata, carried through so the email can still be archived
        // if the content fetch fails.
        from: v.string(),
        to: v.array(v.string()),
        cc: v.array(v.string()),
        bcc: v.array(v.string()),
        receivedFor: v.array(v.string()),
        subject: v.string(),
        messageId: v.string(),
        attachments: v.array(supportEmailAttachment),
    },
    returns: v.null(),
    handler: async (ctx: ActionCtx, args): Promise<null> => {
        // `html_format: 'cid'` keeps inline images as `cid:` references. The
        // default ('data_uri') base64-inlines every image into `html`, which
        // would push a picture-heavy email past Convex's 1 MiB document limit.
        const content = await getResendClient()
            .emails.receiving.get(args.resendEmailId, { html_format: 'cid' })
            .catch((error: unknown) => ({
                data: null,
                error: { message: errorMessage(error) },
            }))

        if (content.error !== null || content.data === null) {
            console.error(
                `support email ${args.resendEmailId}: could not fetch content (${content.error?.message ?? 'unknown error'}); archiving webhook metadata only`,
            )
        }

        const email = content.data
        const bodies = capBodies(email?.html ?? null, email?.text ?? null)
        const from = email?.from ?? args.from

        const stored: { id: Id<'supportEmails'>; alreadyStored: boolean } =
            await ctx.runMutation(
                internal.support.internal.recordInboundEmail,
                {
                    resendEmailId: args.resendEmailId,
                    from,
                    to: email?.to ?? args.to,
                    cc: email?.cc ?? args.cc,
                    bcc: email?.bcc ?? args.bcc,
                    replyTo: email?.reply_to ?? [],
                    receivedFor: email?.received_for ?? args.receivedFor,
                    subject: email?.subject ?? args.subject,
                    messageId: email?.message_id ?? args.messageId,
                    html: bodies.html,
                    text: bodies.text,
                    bodyTruncated: bodies.truncated,
                    attachments:
                        email?.attachments.map((attachment) => ({
                            id: attachment.id,
                            filename: attachment.filename,
                            size: attachment.size,
                            contentType: attachment.content_type,
                            contentId: attachment.content_id,
                            contentDisposition: attachment.content_disposition,
                        })) ?? args.attachments,
                    receivedAt: args.receivedAt,
                },
            )

        // A Resend webhook retry re-delivers an email already archived and
        // already forwarded. Stop here rather than sending the support inbox a
        // duplicate copy.
        if (stored.alreadyStored) {
            console.info(
                `support email ${args.resendEmailId} was already archived; skipping duplicate forward`,
            )
            return null
        }

        const outcome = await forwardEmail(args.resendEmailId, from)
        await ctx.runMutation(internal.support.internal.markForwardResult, {
            id: stored.id,
            status: outcome.status,
            forwardTo: outcome.forwardTo,
            forwardResendEmailId: outcome.forwardResendEmailId,
            forwardError: outcome.forwardError,
        })
        return null
    },
})
