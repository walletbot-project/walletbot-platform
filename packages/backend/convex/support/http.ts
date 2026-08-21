import type { HttpRouter } from 'convex/server'
import type { WebhookEventPayload } from 'resend'
import { internal } from '../_generated/api'
import { httpAction } from '../_generated/server'
import {
    errorMessage,
    getInboundWebhookSecret,
    getResendClient,
    isSupportRecipient,
    parseTimestamp,
    SUPPORT_ADDRESSES,
} from './utils'

// Resend signs webhooks with Svix and documents the `svix-*` header names
// (resend.com/docs/webhooks/verify-webhooks-requests); the Standard Webhooks
// `webhook-*` aliases are accepted as a fallback since the SDK normalises to
// those names internally.
const signatureHeader = (headers: Headers, name: string): string | null =>
    headers.get(`svix-${name}`) ?? headers.get(`webhook-${name}`)

// Throws when the signature does not check out. The SDK's own verifier is used
// instead of a direct `svix` dependency — `resend` already bundles the Standard
// Webhooks implementation, which is pure JS and runs in Convex's default
// runtime.
const verifyEvent = (
    payload: string,
    headers: Headers,
): WebhookEventPayload => {
    const id = signatureHeader(headers, 'id')
    const timestamp = signatureHeader(headers, 'timestamp')
    const signature = signatureHeader(headers, 'signature')
    if (id === null || timestamp === null || signature === null) {
        throw new Error('request carries no webhook signature headers')
    }
    return getResendClient().webhooks.verify({
        payload,
        headers: { id, timestamp, signature },
        webhookSecret: getInboundWebhookSecret(),
    })
}

/**
 * POST /resend-inbound-webhook — Resend `email.received` events.
 *
 * A second, separate route from `/resend-webhook` (which the
 * `@convex-dev/resend` component owns for delivery events) because Resend
 * issues one signing secret per webhook endpoint, and because that component
 * only knows about emails *it* sent: its handler looks an event's `email_id`
 * up in its own table and drops anything it cannot find, so an inbound email
 * routed there would be silently discarded.
 *
 * No CORS headers and no OPTIONS route — this is a server-to-server webhook,
 * never called from a browser.
 */
const inboundEmailHandler = httpAction(async (ctx, req) => {
    // Must be the raw body: "parsing the request as JSON before stringifying
    // it will break signature verification"
    // (resend.com/docs/webhooks/verify-webhooks-requests).
    const raw = await req.text()

    let event: WebhookEventPayload
    try {
        event = verifyEvent(raw, req.headers)
    } catch (error) {
        // 401 rather than 500: an unsigned or missigned request is not
        // something Resend should retry.
        console.error(`inbound email webhook rejected: ${errorMessage(error)}`)
        return new Response(null, { status: 401 })
    }

    if (event.type !== 'email.received') {
        console.info(
            `inbound email webhook ignoring ${event.type}; delivery events belong to /resend-webhook`,
        )
        return new Response(null, { status: 200 })
    }

    // MX records make Resend accept mail for every address at the domain, so
    // the recipient filter is what scopes this pipeline to the support
    // mailboxes.
    if (!isSupportRecipient(event.data)) {
        console.info(
            `inbound email ${event.data.email_id} was not addressed to ${SUPPORT_ADDRESSES.join(' or ')}; ignoring`,
        )
        return new Response(null, { status: 200 })
    }

    // Hand off and answer immediately. Fetching the body and forwarding are
    // two more calls to Resend's API; doing them inline would risk the webhook
    // timing out and being retried for work already in flight.
    await ctx.scheduler.runAfter(
        0,
        internal.support.actions.processInboundEmail,
        {
            resendEmailId: event.data.email_id,
            receivedAt: parseTimestamp(event.data.created_at, Date.now()),
            from: event.data.from,
            to: event.data.to,
            cc: event.data.cc,
            bcc: event.data.bcc,
            receivedFor: event.data.received_for,
            subject: event.data.subject,
            messageId: event.data.message_id,
            attachments: event.data.attachments.map((attachment) => ({
                id: attachment.id,
                filename: attachment.filename,
                // The webhook payload carries no size; only `receiving.get`
                // does, and the action overwrites these when that call works.
                size: null,
                contentType: attachment.content_type,
                contentId: attachment.content_id,
                contentDisposition: attachment.content_disposition,
            })),
        },
    )

    return new Response(null, { status: 202 })
})

export const registerSupportRoutes = (http: HttpRouter): void => {
    http.route({
        path: '/resend-inbound-webhook',
        method: 'POST',
        handler: inboundEmailHandler,
    })
}
