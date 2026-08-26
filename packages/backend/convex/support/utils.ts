import { Resend } from 'resend'

/**
 * The inbound mailboxes this pipeline accepts. `soporte@` is the Spanish
 * spelling of the same mailbox — both land in the same table and forward to the
 * same destination. The legal documents publish `support@`, so that one is the
 * address of record; `soporte@` exists so a Spanish-speaking user writing the
 * obvious address is not silently dropped.
 *
 * Once MX records point walletbot.live at Resend, Resend accepts mail for
 * *every* address at the domain — "Once MX records are configured for a domain
 * or subdomain, you will receive emails sent to any address at that domain.
 * You can filter or route these emails based on the recipient address provided
 * in the webhook event" (resend.com/docs/dashboard/receiving/introduction).
 * Without this filter the table would absorb the whole domain's spam and
 * forward it to the support inbox.
 */
export const SUPPORT_ADDRESSES: readonly string[] = [
    'support@walletbot.live',
    'soporte@walletbot.live',
]

const isSupportAddress = (address: string): boolean =>
    SUPPORT_ADDRESSES.includes(address)

/**
 * Convex caps a document at 1 MiB, measured on the UTF-8 bytes of its strings,
 * so these are byte budgets and not character counts: a character costs 1 to 4
 * bytes, and 512 K *characters* of CJK or emoji is over 1.5 MiB. Truncating by
 * character count would let such a body through and fail the insert, which
 * loses the email rather than shortening it. The two budgets together take
 * 640 KiB, leaving the rest of the row (addresses, subject, attachment
 * metadata) room under the limit.
 *
 * `receiving.get` is called with `html_format: 'cid'` so inline images stay as
 * `cid:` references instead of base64 `data:` URIs (the default, which would
 * inline every image into the body), but a long quoted thread can still be
 * large on its own. Cap both bodies and record `bodyTruncated` on the row.
 */
const MAX_HTML_BYTES = 512 * 1024
const MAX_TEXT_BYTES = 128 * 1024

/**
 * Fallback envelope sender for the forwarded copy. Must be an address on a
 * Resend-verified domain; `no-reply@walletbot.live` is the one this deployment
 * already sends from (`emails/nodeActions.ts`).
 *
 * Note this is the `From` the Gmail recipient sees, so replying from Gmail
 * answers *us*, not the person who wrote in. The original sender stays visible
 * in the forwarded body (passthrough forwarding preserves the message) and in
 * the archived row's `from`.
 */
const DEFAULT_FORWARD_FROM = 'Wallet Bot Support <no-reply@walletbot.live>'

const requireEnv = (name: string): string => {
    const value = process.env[name]
    if (typeof value !== 'string' || value.length === 0) {
        throw new Error(`${name} environment variable is not set`)
    }
    return value
}

const optionalEnv = (name: string): string | null => {
    const value = process.env[name]?.trim()
    return value ? value : null
}

// The SDK reads RESEND_API_KEY itself, but it throws a generic "Missing API
// key" that says nothing about which deployment is misconfigured. Read it
// through requireEnv so a missing key names itself, like every other env var
// in this backend (`authNative/utils.ts`).
export const getResendClient = (): Resend =>
    new Resend(requireEnv('RESEND_API_KEY'))

/**
 * Signing secret of the Resend webhook that points at `/resend-inbound-webhook`.
 *
 * Deliberately NOT the same env var as `RESEND_WEBHOOK_SECRET`: Resend issues
 * one signing secret per webhook endpoint, and delivery events keep going to
 * `/resend-webhook` (the `@convex-dev/resend` component's handler).
 */
export const getInboundWebhookSecret = (): string =>
    requireEnv('RESEND_INBOUND_WEBHOOK_SECRET')

/**
 * Destination the support mail is redirected to (the Gmail address). Runtime
 * knob — `npx convex env set SUPPORT_FORWARD_TO someone@gmail.com` — so
 * changing who reads support mail needs no deploy.
 *
 * `null` (unset) means "archive only": the email is still stored, the forward
 * is recorded as `skipped`. Storing must not depend on a forwarding target
 * being configured.
 */
export const getForwardTo = (): string | null =>
    optionalEnv('SUPPORT_FORWARD_TO')

export const getForwardFrom = (): string =>
    optionalEnv('SUPPORT_FORWARD_FROM') ?? DEFAULT_FORWARD_FROM

/** `"Name <user@host>"` → `"user@host"`; a bare address passes through. */
export const extractAddress = (value: string): string => {
    const angled = value.match(/<([^>]+)>/)
    const address = angled ? angled[1] : value
    return address.trim().toLowerCase()
}

const includesSupportAddress = (values: readonly string[]): boolean =>
    values.some((value) => isSupportAddress(extractAddress(value)))

/**
 * True when the message was actually addressed to the support mailbox.
 *
 * `received_for` is checked alongside the visible headers because a message
 * relayed through another address arrives with the support address only there,
 * and `bcc` because a blind copy never shows up in `to`/`cc`.
 */
export const isSupportRecipient = (data: {
    to: readonly string[]
    cc: readonly string[]
    bcc: readonly string[]
    received_for: readonly string[]
}): boolean =>
    includesSupportAddress(data.to) ||
    includesSupportAddress(data.cc) ||
    includesSupportAddress(data.bcc) ||
    includesSupportAddress(data.received_for)

/**
 * Refuses to forward mail that would bounce straight back into this pipeline:
 * a message sent from any of the support mailboxes itself, or from the forward
 * destination. Without it, one auto-reply on either end is a mail loop that
 * bills every hop.
 */
export const isForwardLoop = (from: string, forwardTo: string): boolean => {
    const sender = extractAddress(from)
    return isSupportAddress(sender) || sender === extractAddress(forwardTo)
}

const utf8Length = (value: string): number =>
    new TextEncoder().encode(value).length

/**
 * Longest prefix of `value` that fits in `maxBytes` UTF-8 bytes.
 *
 * Binary search on the character index because byte budget and string index do
 * not line up. `maxBytes` is a safe upper bound for the index: a character
 * never encodes to fewer bytes than the UTF-16 units it occupies.
 */
export const truncateToBytes = (value: string, maxBytes: number): string => {
    if (utf8Length(value) <= maxBytes) return value

    let low = 0
    let high = Math.min(value.length, maxBytes)
    while (low < high) {
        const mid = Math.ceil((low + high) / 2)
        if (utf8Length(value.slice(0, mid)) <= maxBytes) low = mid
        else high = mid - 1
    }

    // Cutting between the halves of a surrogate pair leaves a lone surrogate,
    // which has no UTF-8 encoding and would be rejected on insert. Drop it.
    const lastUnit = value.charCodeAt(low - 1)
    if (lastUnit >= 0xd800 && lastUnit <= 0xdbff) return value.slice(0, low - 1)
    return value.slice(0, low)
}

type Body = { html: string | null; text: string | null; truncated: boolean }

export const capBodies = (html: string | null, text: string | null): Body => {
    const cappedHtml =
        html === null ? null : truncateToBytes(html, MAX_HTML_BYTES)
    const cappedText =
        text === null ? null : truncateToBytes(text, MAX_TEXT_BYTES)
    return {
        html: cappedHtml,
        text: cappedText,
        truncated: cappedHtml !== html || cappedText !== text,
    }
}

/**
 * Resend sends timestamps as ISO strings. An unparseable one must not abort
 * archiving an otherwise valid email, so fall back to now.
 */
export const parseTimestamp = (iso: string, now: number): number => {
    const parsed = Date.parse(iso)
    return Number.isFinite(parsed) ? parsed : now
}

export const errorMessage = (error: unknown): string =>
    error instanceof Error ? error.message : String(error)
