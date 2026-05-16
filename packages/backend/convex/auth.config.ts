import { getAuthConfigProvider } from '@convex-dev/better-auth/auth-config'
import type { AuthConfig } from 'convex/server'

// Native clients receive JWTs minted by `convex/authNative/http.ts`, signed
// with `JWT_PRIVATE_KEY` and verified by Convex via the JWKS we serve at
// `${CONVEX_SITE_URL}/native-auth/.well-known/jwks.json`. The `/native-auth`
// prefix is required because better-auth's component already owns
// `/.well-known/openid-configuration` on the bare site URL.
const convexSiteUrl = process.env.CONVEX_SITE_URL
const nativeIssuer = convexSiteUrl ? `${convexSiteUrl}/native-auth` : undefined

export default {
    providers: [
        getAuthConfigProvider(),
        ...(nativeIssuer
            ? [
                  {
                      domain: nativeIssuer,
                      applicationID: 'walletbot-native' as const,
                  },
              ]
            : []),
    ],
} satisfies AuthConfig
