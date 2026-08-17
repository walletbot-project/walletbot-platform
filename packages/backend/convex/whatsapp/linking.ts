// Pure link-code logic: generation, normalisation and extraction.
//
// Kept free of Convex and Node imports so it can be used from the default
// runtime, from a `'use node'` action, and from tests without a database.
//
// Why a code at all: the WhatsApp webhook is a public, unauthenticated
// endpoint — anyone who knows the business number can send it a message. So a
// wa_id can never be trusted to identify a user on its own. Linking starts in
// an authenticated app session, which mints a code; sending that code over
// WhatsApp proves the same person holds both. Until that happens the
// conversation has no userId and the agent is never invoked.

// Crockford base32: no I, L, O or U. Removing them means a code can be read
// aloud or typed from a screen without the 0/O and 1/I/l confusions, and
// dropping U avoids accidental profanity.
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'

export const LINK_CODE_LENGTH = 8

// 32^8 ≈ 1.1e12. Combined with a 10-minute expiry and the per-conversation
// attempt limit, online guessing is not a viable attack.
const DIGITS = '0123456789'

export const LINK_CODE_TTL_MS = 10 * 60 * 1000

// Crockford's canonical aliases, so a user who types the letter O or a lower-
// case l still links successfully.
const ALIASES: Record<string, string> = {
    O: '0',
    I: '1',
    L: '1',
    U: 'V',
}

const hasDigit = (value: string): boolean =>
    value.split('').some((char) => DIGITS.includes(char))

const hasLetter = (value: string): boolean =>
    value.split('').some((char) => !DIGITS.includes(char))

// Generates a code containing at least one digit and at least one letter.
//
// The mixed-case requirement is not cosmetic: extraction uses it to tell a code
// apart from an ordinary word. Without it, a message like "VINCULAR" would be
// read as a candidate code and burn one of the user's attempts. Rejection
// costs ~5% of draws and about 0.08 bits of entropy, which is free at this
// size.
//
// `byte % 32` is unbiased because 32 divides 256 exactly — with an alphabet
// whose length is not a power of two this would need rejection sampling.
export const generateLinkCode = (): string => {
    for (let attempt = 0; attempt < 16; attempt += 1) {
        const bytes = new Uint8Array(LINK_CODE_LENGTH)
        crypto.getRandomValues(bytes)
        const code = Array.from(
            bytes,
            (byte) => ALPHABET[byte % ALPHABET.length],
        ).join('')
        if (hasDigit(code) && hasLetter(code)) return code
    }
    // 16 consecutive rejections has probability ~5.2%^16 ≈ 1e-21. Throwing
    // beats returning a code that violates the extraction contract.
    throw new Error('failed to generate a link code')
}

// Display form: `A1B2-C3D4`. The hyphen is cosmetic and is stripped on the way
// back in.
export const formatLinkCode = (code: string): string =>
    `${code.slice(0, 4)}-${code.slice(4)}`

// Returns the canonical code for a single token, or null if the token is not
// shaped like a code at all.
export const normalizeLinkCode = (raw: string): string | null => {
    const token = raw.trim().toUpperCase().replaceAll('-', '')
    if (token.length !== LINK_CODE_LENGTH) return null
    // Checked before aliasing. Aliasing maps I and L to 1, so a plain word
    // could otherwise acquire a digit it never had and pass as a code.
    if (!hasDigit(token) || !hasLetter(token)) return null

    let normalized = ''
    for (const char of token) {
        const mapped = ALIASES[char] ?? char
        if (!ALPHABET.includes(mapped)) return null
        normalized += mapped
    }
    return normalized
}

// Pulls every code-shaped token out of a message body.
//
// Users paste the deep link's prefilled text, type the code alone, or wrap it
// in a sentence, so scan rather than requiring an exact match. Anything that
// does not look like a code is ignored instead of counting as a failed
// attempt — see the digit/letter rule above.
export const extractLinkCodeCandidates = (text: string): string[] => {
    const candidates: string[] = []
    for (const token of text.split(/[^0-9A-Za-z-]+/)) {
        if (token.length === 0) continue
        const normalized = normalizeLinkCode(token)
        if (normalized && !candidates.includes(normalized)) {
            candidates.push(normalized)
        }
    }
    return candidates
}

export type LinkOutcome =
    | { kind: 'linked' }
    | { kind: 'already_linked' }
    | { kind: 'already_used' }
    | { kind: 'expired' }
    | { kind: 'no_code' }
    | { kind: 'invalid'; attemptsLeft: number }
    | { kind: 'blocked'; until: number }

export type ReplyLanguage = 'es' | 'en'

// Calling codes whose speakers get Spanish. Hard-coded rather than derived from
// a locale library: this runs before there is any account, so the wa_id's
// country code is the only signal available, and a fixed table is auditable.
//
// Two deliberate exclusions:
//   - Brazil (55) is in Latin America but speaks Portuguese, so it gets
//     English. The dividing line here is Spanish, not geography.
//   - NANP (+1) gets English, which also means the Dominican Republic
//     (1809/1829/1849) and Puerto Rico (1787/1939) get English despite being
//     Spanish-speaking. Their numbers are indistinguishable from any other +1
//     number without an area-code table, and over-reaching would hand Spanish
//     to every US and Canadian number.
//
// E.164 country codes are prefix-free, so no code here is a prefix of another
// and the longest-match sort below is belt-and-braces.
const SPANISH_CALLING_CODES = [
    '34', // Spain
    '51', // Peru
    '52', // Mexico
    '53', // Cuba
    '54', // Argentina
    '56', // Chile
    '57', // Colombia
    '58', // Venezuela
    '502', // Guatemala
    '503', // El Salvador
    '504', // Honduras
    '505', // Nicaragua
    '506', // Costa Rica
    '507', // Panama
    '591', // Bolivia
    '593', // Ecuador
    '595', // Paraguay
    '598', // Uruguay
].sort((a, b) => b.length - a.length)

// Picks the reply language from the sender's wa_id.
//
// The wa_id starts with the country calling code and has no `+`, so a prefix
// match is enough. Anything unrecognised falls back to English rather than
// guessing.
export const replyLanguageFor = (waId: string): ReplyLanguage => {
    const digits = waId.replace(/\D/g, '')
    for (const code of SPANISH_CALLING_CODES) {
        if (digits.startsWith(code)) return 'es'
    }
    return 'en'
}

// UTC offsets in minutes, by calling code. Same shape and same reasoning as
// the language table above: a wa_id is the only signal available, there is no
// stored timezone on the account, and a fixed table is auditable.
//
// This exists because "hoy" has to mean the user's today. Convex runs in UTC,
// so an expense reported at 22:00 in Buenos Aires would otherwise be filed
// under tomorrow — and the calendar day is the axis a finance app is read
// along. See `agent/time.ts` for how the offset is applied, including the
// deliberate absence of DST handling.
//
// Countries spanning several zones are pinned to the one holding most of the
// population and most of the WhatsApp traffic (Brazil → São Paulo, Mexico →
// Mexico City, US/Canada → New York), which is wrong for a minority of users
// by one to three hours.
const UTC_OFFSET_MINUTES: Record<string, number> = {
    '1': -300, // US / Canada — Eastern
    '34': 60, // Spain
    '51': -300, // Peru
    '52': -360, // Mexico
    '53': -300, // Cuba
    '54': -180, // Argentina
    '55': -180, // Brazil
    '56': -180, // Chile (no DST modelled)
    '57': -300, // Colombia
    '58': -240, // Venezuela
    '502': -360, // Guatemala
    '503': -360, // El Salvador
    '504': -360, // Honduras
    '505': -360, // Nicaragua
    '506': -360, // Costa Rica
    '507': -300, // Panama
    '591': -240, // Bolivia
    '593': -300, // Ecuador
    '595': -180, // Paraguay (no DST modelled)
    '598': -180, // Uruguay
}

// Longest prefix first so `502` is not shadowed by a hypothetical `50`.
// E.164 codes are prefix-free, so this is belt-and-braces.
const OFFSET_CODES = Object.keys(UTC_OFFSET_MINUTES).sort(
    (a, b) => b.length - a.length,
)

// Falls back to Argentina rather than UTC: every number this reaches today is
// Argentine, and UTC would be wrong for all of them. Revisit when the product
// ships outside the region.
export const DEFAULT_UTC_OFFSET_MINUTES = -180

export const utcOffsetMinutesFor = (waId: string): number => {
    const digits = waId.replace(/\D/g, '')
    for (const code of OFFSET_CODES) {
        if (digits.startsWith(code)) return UTC_OFFSET_MINUTES[code]
    }
    return DEFAULT_UTC_OFFSET_MINUTES
}

// Copy for the only messages Wallet Bot sends to a number it cannot identify.
//
// One language, never both. At this point there is no account and therefore no
// stored locale, so the language comes from the sender's country code
// ([replyLanguageFor]). Every later message happens after linking, where the
// agent follows the user's own words instead.
//
// Returns null when the right answer is to stay silent. A blocked conversation
// gets no reply at all: answering would make the attempt limit into a free
// oracle that confirms the number is reachable and keeps costing us sends.
export const linkReplyText = (
    outcome: LinkOutcome,
    language: ReplyLanguage,
): string | null => {
    const es = language === 'es'
    switch (outcome.kind) {
        case 'linked':
        case 'already_linked':
            return es
                ? '✅ Listo, tu número quedó vinculado a Wallet Bot. Ya podés escribirme tus gastos.'
                : '✅ Your number is now linked to Wallet Bot. Go ahead and tell me about your expenses.'
        case 'already_used':
            return es
                ? 'Ese código ya fue usado y tu número ya está vinculado.'
                : 'That code was already used — your number is linked.'
        case 'expired':
            return es
                ? 'Ese código venció. Generá uno nuevo desde la app y enviámelo.'
                : 'That code has expired. Generate a new one in the app and send it to me.'
        case 'invalid':
            return es
                ? `Ese código no es válido. Te quedan ${outcome.attemptsLeft} intento(s).`
                : `That code is not valid. You have ${outcome.attemptsLeft} attempt(s) left.`
        case 'no_code':
            return es
                ? 'Hola 👋 Soy Wallet Bot. Para empezar, generá un código de vinculación en la app y enviámelo por acá.'
                : 'Hi 👋 I am Wallet Bot. To get started, generate a link code in the app and send it to me here.'
        case 'blocked':
            return null
    }
}

// `wa.me` takes the *dialable* number in international format without the `+`,
// which for several countries is not the wa_id — see the wa_id trap in
// docs/whatsapp-platform.md. Returns null when the number is not configured so
// callers fall back to showing the code on its own.
export const buildLinkDeepLink = (
    businessNumber: string | undefined,
    code: string,
): string | null => {
    const digits = (businessNumber ?? '').replace(/\D/g, '')
    if (digits.length === 0) return null
    const text = encodeURIComponent(`Wallet Bot: ${formatLinkCode(code)}`)
    return `https://wa.me/${digits}?text=${text}`
}
