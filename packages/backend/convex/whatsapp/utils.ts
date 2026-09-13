// Private helpers for the WhatsApp webhook: signature verification and payload
// parsing. Nothing outside this feature should need either, so they stay here
// rather than in helpers.ts.
//
// This file deliberately uses only Web Crypto and stays out of the Node
// runtime, so http.ts (the shared router) is never forced into `'use node'`.

const encoder = new TextEncoder()

const toHex = (bytes: Uint8Array): string =>
    Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')

// Constant-time compare. `crypto.timingSafeEqual` is Node-only and this file
// runs in the default runtime, so compare every character without an early
// exit — a length-dependent or content-dependent return time would leak the
// expected signature one byte at a time.
const timingSafeEqual = (a: string, b: string): boolean => {
    if (a.length !== b.length) return false
    let diff = 0
    for (let i = 0; i < a.length; i += 1) {
        diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
    }
    return diff === 0
}

// Meta signs the raw request body with the app secret:
//   X-Hub-Signature-256: sha256=<hex>
//
// Two rules matter and both are easy to get wrong. The HMAC must be computed
// over the *exact* bytes Meta sent — parsing and re-serializing the JSON
// changes them and the signature will never match — and the comparison must be
// timing-safe. Without this check the webhook is an unauthenticated public
// endpoint that writes straight into the agent's context.
export const verifySignature = async (
    rawBody: string,
    signatureHeader: string | null,
    appSecret: string,
): Promise<boolean> => {
    const prefix = 'sha256='
    if (!signatureHeader?.startsWith(prefix)) return false
    const key = await crypto.subtle.importKey(
        'raw',
        encoder.encode(appSecret),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign'],
    )
    const signed = await crypto.subtle.sign(
        'HMAC',
        key,
        encoder.encode(rawBody),
    )
    return timingSafeEqual(
        toHex(new Uint8Array(signed)),
        signatureHeader.slice(prefix.length),
    )
}

export type ParsedInboundMessage = {
    wamid: string
    waId: string
    phoneNumberId: string
    type: string
    text?: string
    mediaId?: string
    sentAt: number
}

export type ParsedStatus = {
    wamid: string
    status: string
    errorCode?: number
    errorMessage?: string
}

export type ParsedWebhook = {
    messages: ParsedInboundMessage[]
    statuses: ParsedStatus[]
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
    typeof value === 'object' && value !== null && !Array.isArray(value)

const asArray = (value: unknown): unknown[] =>
    Array.isArray(value) ? value : []

const asString = (value: unknown): string | null =>
    typeof value === 'string' && value.length > 0 ? value : null

// Meta sends timestamps as seconds, in a string.
const asTimestampMs = (value: unknown, fallback: number): number => {
    const raw = asString(value)
    if (!raw) return fallback
    const seconds = Number.parseInt(raw, 10)
    return Number.isFinite(seconds) ? seconds * 1000 : fallback
}

// Media-bearing message types all carry `{ id, mime_type, ... }` under a key
// named after the type, so one lookup covers image/audio/video/document/sticker.
const mediaIdFor = (
    message: Record<string, unknown>,
    type: string,
): string | undefined => {
    const media = message[type]
    if (!isRecord(media)) return undefined
    return asString(media.id) ?? undefined
}

const textBodyFor = (
    message: Record<string, unknown>,
    type: string,
): string | undefined => {
    if (type === 'text') {
        const text = message.text
        return isRecord(text) ? (asString(text.body) ?? undefined) : undefined
    }
    // Interactive replies (buttons, list picks) carry the user's choice as a
    // title; treating it as text means the agent needs no special case.
    if (type === 'interactive') {
        const interactive = message.interactive
        if (!isRecord(interactive)) return undefined
        for (const key of ['button_reply', 'list_reply']) {
            const reply = interactive[key]
            if (isRecord(reply)) return asString(reply.title) ?? undefined
        }
        return undefined
    }
    if (type === 'button') {
        const button = message.button
        return isRecord(button)
            ? (asString(button.text) ?? undefined)
            : undefined
    }
    // Media captions are the user's words too, so surface them as text.
    const media = message[type]
    if (isRecord(media)) return asString(media.caption) ?? undefined
    return undefined
}

// Walks entry[].changes[].value and pulls out inbound messages and status
// updates. Written defensively: a shape we don't recognise is skipped rather
// than thrown on, because throwing would make Meta retry the delivery forever.
export const parseWebhookPayload = (
    payload: unknown,
    receivedAt: number,
): ParsedWebhook => {
    const messages: ParsedInboundMessage[] = []
    const statuses: ParsedStatus[] = []
    if (!isRecord(payload)) return { messages, statuses }

    for (const entry of asArray(payload.entry)) {
        if (!isRecord(entry)) continue
        for (const change of asArray(entry.changes)) {
            if (!isRecord(change)) continue
            const value = change.value
            if (!isRecord(value)) continue

            const metadata = isRecord(value.metadata) ? value.metadata : {}
            const phoneNumberId = asString(metadata.phone_number_id)
            if (!phoneNumberId) continue

            for (const raw of asArray(value.messages)) {
                if (!isRecord(raw)) continue
                const wamid = asString(raw.id)
                // `from` is the sender's wa_id — the canonical identity. Never
                // reconstruct it from a phone number: see the wa_id trap in
                // docs/whatsapp-platform.md.
                const waId = asString(raw.from)
                const type = asString(raw.type)
                if (!wamid || !waId || !type) continue
                messages.push({
                    wamid,
                    waId,
                    phoneNumberId,
                    type,
                    text: textBodyFor(raw, type),
                    mediaId: mediaIdFor(raw, type),
                    sentAt: asTimestampMs(raw.timestamp, receivedAt),
                })
            }

            for (const raw of asArray(value.statuses)) {
                if (!isRecord(raw)) continue
                const wamid = asString(raw.id)
                const status = asString(raw.status)
                if (!wamid || !status) continue
                const firstError = asArray(raw.errors).find(isRecord)
                statuses.push({
                    wamid,
                    status,
                    errorCode:
                        firstError && typeof firstError.code === 'number'
                            ? firstError.code
                            : undefined,
                    errorMessage: firstError
                        ? (asString(firstError.title) ??
                          asString(firstError.message) ??
                          undefined)
                        : undefined,
                })
            }
        }
    }

    return { messages, statuses }
}
