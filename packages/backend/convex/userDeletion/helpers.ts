// Token hygiene for the account-deletion email flow. Same construction as
// the native session tokens (authNative/utils.ts): 32 random bytes rendered
// as hex for the URL, SHA-256 hex stored server-side. Duplicated here instead
// of imported because authNative/utils.ts is private to that feature.

const DELETION_TOKEN_BYTES = 32

// The emailed link stays valid for 24 hours (matches the email copy).
export const DELETION_TOKEN_TTL_MS = 24 * 60 * 60 * 1000

// At most this many deletion emails per address per hour.
export const MAX_REQUESTS_PER_HOUR = 3

const toHex = (bytes: Uint8Array): string => {
    let out = ''
    for (let i = 0; i < bytes.length; i++) {
        out += bytes[i].toString(16).padStart(2, '0')
    }
    return out
}

export const generateDeletionToken = (): string => {
    const buf = new Uint8Array(DELETION_TOKEN_BYTES)
    crypto.getRandomValues(buf)
    return toHex(buf)
}

export const hashDeletionToken = async (token: string): Promise<string> => {
    const digest = await crypto.subtle.digest(
        'SHA-256',
        new TextEncoder().encode(token),
    )
    return toHex(new Uint8Array(digest))
}
