import { createClient, type GenericCtx } from '@convex-dev/better-auth'
import { convex, crossDomain } from '@convex-dev/better-auth/plugins'
import { betterAuth } from 'better-auth/minimal'
import { bearer } from 'better-auth/plugins'
import { components } from './_generated/api'
import type { DataModel } from './_generated/dataModel'
import authConfig from './auth.config'

const siteUrl = process.env.SITE_URL!
const convexSiteUrl = process.env.CONVEX_SITE_URL

const appleClientId = process.env.APPLE_CLIENT_ID
const appleBundleId = process.env.APPLE_BUNDLE_ID

// Google mints the native ID token for a different OAuth client per platform.
// Android's plugin uses `serverClientId` (our web client), but Google Sign-In
// for iOS issues the token for the app's own client — Info.plist `GIDClientID`
// — and spends `serverClientId` on the server auth code instead. So an iOS
// token carries an `aud` the web client ID doesn't match, and better-auth's
// `verifyIdToken` rejects it with a 401 `INVALID_TOKEN`.
//
// Listing both makes the iOS client an additional accepted audience. The first
// entry stays primary: it is the one used to build the web authorization URL.
// Both clients must belong to the same Google project so consent is shared.
// Falls back to the web client alone when the iOS client isn't configured, so
// a deployment missing this var keeps working exactly as before.
const googleClientId = process.env.GOOGLE_CLIENT_ID as string
const googleIosClientId = process.env.GOOGLE_IOS_CLIENT_ID

// The component client has methods needed for integrating Convex with Better Auth,
// as well as helper methods for general use.
export const authComponent = createClient<DataModel>(components.betterAuth)

export const createAuth = (ctx: GenericCtx<DataModel>) => {
    return betterAuth({
        baseURL: convexSiteUrl,
        trustedOrigins: [siteUrl, 'flutter://'],
        database: authComponent.adapter(ctx),
        // Configure simple, non-verified email/password to get started
        emailAndPassword: {
            enabled: true,
            requireEmailVerification: false,
        },
        socialProviders: {
            google: {
                clientId: googleIosClientId
                    ? [googleClientId, googleIosClientId]
                    : googleClientId,
                clientSecret: process.env.GOOGLE_CLIENT_SECRET as string,
            },
            ...(appleClientId
                ? {
                      apple: {
                          clientId: appleClientId,
                          appBundleIdentifier: appleBundleId,
                      },
                  }
                : {}),
        },
        plugins: [
            // Accept session tokens via `Authorization: Bearer <token>` header.
            // The native app uses this because dio's cookie_jar isn't reliable
            // for our use case (cookies don't survive app restarts).
            bearer(),
            // The cross domain plugin is required for client side frameworks
            crossDomain({ siteUrl }),
            // The Convex plugin is required for Convex compatibility
            convex({ authConfig }),
        ],
    })
}
