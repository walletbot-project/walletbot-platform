// Outbound WhatsApp helpers. Exported so other features (reminders, alerts) can
// send without going through the agent.
//
// Plain `fetch` only — no Node APIs — so a `'use node'` caller may import this
// safely under the import-chain rule in CLAUDE.md.

// WhatsApp rejects text bodies over 4096 characters.
const MAX_BODY_CHARS = 4096

const requireEnv = (name: string): string => {
    const value = process.env[name]
    if (typeof value !== 'string' || value.length === 0) {
        throw new Error(`${name} environment variable is not set`)
    }
    return value
}

const graphVersion = (): string => process.env.WHATSAPP_GRAPH_VERSION ?? 'v23.0'

export type SendResult =
    | { ok: true; wamid: string }
    | { ok: false; errorCode?: number; errorMessage: string }

// The service window is enforced here, on our side, because Meta will accept an
// out-of-window free-form send with `200` + a wamid and then silently discard
// it (verified 2026-08-16). Checking first turns an invisible failure into a
// visible one.
export const windowIsOpen = (
    windowExpiresAt: number,
    now: number = Date.now(),
): boolean => now < windowExpiresAt

const isRecord = (value: unknown): value is Record<string, unknown> =>
    typeof value === 'object' && value !== null && !Array.isArray(value)

// Splits on paragraph, then line, then hard-cuts — so a long agent reply keeps
// its structure instead of being sliced mid-word.
export const chunkBody = (text: string): string[] => {
    if (text.length <= MAX_BODY_CHARS) return [text]
    const chunks: string[] = []
    let remaining = text
    while (remaining.length > MAX_BODY_CHARS) {
        const slice = remaining.slice(0, MAX_BODY_CHARS)
        let cut = slice.lastIndexOf('\n\n')
        if (cut < MAX_BODY_CHARS / 2) cut = slice.lastIndexOf('\n')
        if (cut < MAX_BODY_CHARS / 2) cut = slice.lastIndexOf(' ')
        if (cut < MAX_BODY_CHARS / 2) cut = MAX_BODY_CHARS
        chunks.push(remaining.slice(0, cut).trimEnd())
        remaining = remaining.slice(cut).trimStart()
    }
    if (remaining.length > 0) chunks.push(remaining)
    return chunks
}

// `to` must be the recipient's wa_id as WhatsApp reported it — never a phone
// number you normalised yourself. For several countries (Argentina, Mexico,
// Brazil) the wa_id differs from the dialable number; see the wa_id trap in
// docs/whatsapp-platform.md.
export const sendText = async (args: {
    phoneNumberId: string
    to: string
    body: string
}): Promise<SendResult> => {
    const token = requireEnv('WHATSAPP_ACCESS_TOKEN')
    const url = `https://graph.facebook.com/${graphVersion()}/${args.phoneNumberId}/messages`

    let response: Response
    try {
        response = await fetch(url, {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${token}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                messaging_product: 'whatsapp',
                recipient_type: 'individual',
                to: args.to,
                type: 'text',
                text: { body: args.body, preview_url: false },
            }),
        })
    } catch (error) {
        return {
            ok: false,
            errorMessage: `network error calling graph api: ${String(error)}`,
        }
    }

    const payload: unknown = await response.json().catch(() => null)

    if (!response.ok) {
        const error =
            isRecord(payload) && isRecord(payload.error) ? payload.error : null
        return {
            ok: false,
            errorCode:
                error && typeof error.code === 'number'
                    ? error.code
                    : undefined,
            errorMessage:
                error && typeof error.message === 'string'
                    ? error.message
                    : `graph api returned ${response.status}`,
        }
    }

    // A wamid means queued, not delivered. Delivery only becomes known when a
    // status webhook updates the outbound row.
    const messages =
        isRecord(payload) && Array.isArray(payload.messages)
            ? payload.messages
            : []
    const first = messages.find(isRecord)
    const wamid = first && typeof first.id === 'string' ? first.id : null
    if (!wamid) {
        return {
            ok: false,
            errorMessage: 'graph api response had no message id',
        }
    }
    return { ok: true, wamid }
}
