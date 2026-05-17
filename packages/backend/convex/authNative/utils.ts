import { type CryptoKey, importPKCS8, SignJWT } from 'jose'

const ACCESS_TOKEN_TTL_SEC = 60
const SESSION_TOKEN_BYTES = 32

const AUDIENCE = 'walletbot-native'

let cachedPrivateKey: CryptoKey | null = null
let cachedKid: string | null = null

const requireEnv = (name: string): string => {
    const value = process.env[name]
    if (typeof value !== 'string' || value.length === 0) {
        throw new Error(`${name} environment variable is not set`)
    }
    return value
}

// Must match `nativeIssuer` in `auth.config.ts`. The `/native-auth` prefix
// keeps our OIDC discovery + JWKS off paths already owned by better-auth.
const getIssuer = (): string => `${requireEnv('CONVEX_SITE_URL')}/native-auth`

const getPrivateKey = async (): Promise<CryptoKey> => {
    if (cachedPrivateKey) return cachedPrivateKey
    const pem = requireEnv('JWT_PRIVATE_KEY')
    cachedPrivateKey = await importPKCS8(pem, 'RS256')
    return cachedPrivateKey
}

const getKid = (): string => {
    if (cachedKid) return cachedKid
    const raw = requireEnv('JWKS')
    const parsed = JSON.parse(raw) as { keys?: Array<{ kid?: string }> }
    const kid = parsed.keys?.[0]?.kid
    if (typeof kid !== 'string' || kid.length === 0) {
        throw new Error('JWKS is missing a kid for its first key')
    }
    cachedKid = kid
    return cachedKid
}

export type MintedAccessToken = {
    token: string
    expiresAt: number // ms epoch
}

export const mintAccessToken = async (
    userId: string,
): Promise<MintedAccessToken> => {
    const key = await getPrivateKey()
    const kid = getKid()
    const issuer = getIssuer()
    const now = Math.floor(Date.now() / 1000)
    const exp = now + ACCESS_TOKEN_TTL_SEC
    const token = await new SignJWT({})
        .setProtectedHeader({ alg: 'RS256', kid, typ: 'JWT' })
        .setIssuer(issuer)
        .setSubject(userId)
        .setAudience(AUDIENCE)
        .setIssuedAt(now)
        .setExpirationTime(exp)
        .sign(key)
    return { token, expiresAt: exp * 1000 }
}

const toHex = (bytes: Uint8Array): string => {
    let out = ''
    for (let i = 0; i < bytes.length; i++) {
        out += bytes[i].toString(16).padStart(2, '0')
    }
    return out
}

const randomHex = (byteLength: number): string => {
    const buf = new Uint8Array(byteLength)
    crypto.getRandomValues(buf)
    return toHex(buf)
}

export const generateSessionSecret = (): string =>
    randomHex(SESSION_TOKEN_BYTES)

export const hashSessionSecret = async (secret: string): Promise<string> => {
    const digest = await crypto.subtle.digest(
        'SHA-256',
        new TextEncoder().encode(secret),
    )
    return toHex(new Uint8Array(digest))
}
