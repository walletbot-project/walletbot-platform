import type { HttpRouter } from 'convex/server'
import { internal } from '../_generated/api'
import { httpAction } from '../_generated/server'
import { parseWebhookPayload, verifySignature } from './utils'

const WEBHOOK_PATH = '/v1/whatsapp/webhook'

// Deliberately no CORS headers and no use of httpHelpers.jsonResponse: this is a
// server-to-server endpoint that must never be callable from a browser page.

// GET — Meta's subscription handshake, sent once when you save the callback URL
// in the App Dashboard. Echo `hub.challenge` verbatim as plain text or Meta
// refuses to save the URL, with no explanation of why.
const verifyWebhook = httpAction(async (_ctx, req) => {
    const url = new URL(req.url)
    const mode = url.searchParams.get('hub.mode')
    const token = url.searchParams.get('hub.verify_token')
    const challenge = url.searchParams.get('hub.challenge')

    const expected = process.env.WHATSAPP_VERIFY_TOKEN
    if (!expected) {
        console.error('WHATSAPP_VERIFY_TOKEN is not set; refusing verification')
        return new Response('not configured', { status: 500 })
    }
    if (mode !== 'subscribe' || token !== expected || !challenge) {
        console.error('whatsapp webhook verification rejected')
        return new Response('forbidden', { status: 403 })
    }
    return new Response(challenge, {
        status: 200,
        headers: { 'Content-Type': 'text/plain' },
    })
})

// POST — every inbound message and every delivery status.
//
// Two hard requirements. It must ack fast, so all real work is a single cheap
// mutation that writes rows and schedules; the agent never runs inline. And the
// signature must be checked against the *raw* body before parsing, because
// re-serialising the JSON changes the bytes and the HMAC would never match.
const receiveWebhook = httpAction(async (ctx, req) => {
    const appSecret = process.env.WHATSAPP_APP_SECRET
    if (!appSecret) {
        // Fail closed. Without the secret we cannot distinguish Meta from an
        // attacker, and this payload feeds straight into the agent. A 500 makes
        // Meta retry, so nothing is lost once the env var is set.
        console.error('WHATSAPP_APP_SECRET is not set; rejecting webhook')
        return new Response('not configured', { status: 500 })
    }

    const rawBody = await req.text()
    const signed = await verifySignature(
        rawBody,
        req.headers.get('x-hub-signature-256'),
        appSecret,
    )
    if (!signed) {
        console.error('whatsapp webhook signature verification failed')
        return new Response('forbidden', { status: 403 })
    }

    let payload: unknown
    try {
        payload = JSON.parse(rawBody)
    } catch {
        // Ack malformed JSON. Returning an error would make Meta retry the same
        // unparseable body indefinitely.
        console.error('whatsapp webhook body was not valid JSON')
        return new Response('ok', { status: 200 })
    }

    const { messages, statuses } = parseWebhookPayload(payload, Date.now())

    if (messages.length > 0) {
        await ctx.runMutation(internal.whatsapp.internal.enqueueInbound, {
            messages,
        })
    }
    if (statuses.length > 0) {
        await ctx.runMutation(internal.whatsapp.internal.applyStatusUpdates, {
            statuses,
        })
    }

    return new Response('ok', { status: 200 })
})

export const registerWhatsappRoutes = (http: HttpRouter): void => {
    http.route({ path: WEBHOOK_PATH, method: 'GET', handler: verifyWebhook })
    http.route({ path: WEBHOOK_PATH, method: 'POST', handler: receiveWebhook })
}
