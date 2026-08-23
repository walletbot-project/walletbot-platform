import { createClient, type GenericCtx } from '@convex-dev/better-auth'
import { convex, crossDomain } from '@convex-dev/better-auth/plugins'
import { requireRunMutationCtx } from '@convex-dev/better-auth/utils'
import { betterAuth } from 'better-auth/minimal'
import { bearer } from 'better-auth/plugins'
import { components, internal } from './_generated/api'
import type { DataModel } from './_generated/dataModel'
import authConfig from './auth.config'
import { sendResetPasswordEmail, sendVerificationEmail } from './emails/helpers'

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

// Emails must land on the web app regardless of which client (web or native)
// triggered them, so the server canonicalizes the link's callbackURL. This
// also sidesteps the crossDomain plugin's redirectTo handling entirely.
const withWebCallback = (rawUrl: string, landingPath: string): string => {
    const url = new URL(rawUrl)
    url.searchParams.set('callbackURL', `${siteUrl}${landingPath}`)
    return url.toString()
}

/**
 * Which sign-up path wrote a user row, from the better-auth endpoint that ran,
 * or `null` when the write is not an account creation we count.
 *
 * `/sign-in/social` only creates a user on its ID-token branch (the redirect
 * branch returns a URL and writes nothing), and the native app is its only
 * caller, always with Google's token. The web social flow creates its user in
 * the OAuth callback instead — a different path, deliberately not counted
 * here, exactly as before.
 */
const accountCreationMethod = (
    path: string | undefined,
): 'email_password' | 'google' | null => {
    switch (path) {
        case '/sign-up/email':
            return 'email_password'
        case '/sign-in/social':
            return 'google'
        default:
            return null
    }
}

export const createAuth = (ctx: GenericCtx<DataModel>) => {
    return betterAuth({
        baseURL: convexSiteUrl,
        trustedOrigins: [siteUrl, 'flutter://'],
        database: authComponent.adapter(ctx),
        emailAndPassword: {
            enabled: true,
            requireEmailVerification: true,
            sendResetPassword: async ({ user, url }) => {
                await sendResetPasswordEmail(requireRunMutationCtx(ctx), {
                    to: user.email,
                    name: user.name ?? null,
                    url: withWebCallback(url, '/reset-password'),
                })
            },
            onPasswordReset: async ({ user }) => {
                // Web sessions die via revokeSessionsOnPasswordReset below;
                // native sessions live in our own refreshTokens table.
                await requireRunMutationCtx(ctx).runMutation(
                    internal.authNative.mutations.revokeAllSessionTokensForUser,
                    { userId: user.id },
                )
            },
            revokeSessionsOnPasswordReset: true,
        },
        databaseHooks: {
            user: {
                create: {
                    // Account-creation telemetry has to hang off the real insert.
                    // With `requireEmailVerification` the sign-up endpoint always
                    // answers `token: null` and returns a SYNTHETIC user for
                    // already-registered emails — deliberately indistinguishable
                    // from a genuine one — so nothing at the endpoint can tell a
                    // new account from a duplicate attempt. This hook only runs
                    // when a row is actually written, so duplicates never count.
                    //
                    // Native Google sign-in is here for the same reason: its
                    // `/sign-in/social` response carries no "is this a new
                    // user" flag at all (`{redirect, token, url, user}`), so
                    // `authNative/http.ts` cannot tell either.
                    //
                    // Terms acceptance is deliberately NOT recorded here. It
                    // would need a `user.additionalFields` entry to reach this
                    // hook, and the better-auth component's `create` validator
                    // is generated from its own schema — an unknown field
                    // fails the whole insert. The auth endpoints record it
                    // directly instead (`authNative/http.ts`).
                    after: async (user, context) => {
                        const authMethod = accountCreationMethod(context?.path)
                        if (authMethod === null) return
                        await requireRunMutationCtx(ctx).runMutation(
                            internal.telemetry.mutations
                                .recordUserAccountCreated,
                            {
                                userId: user.id,
                                authMethod,
                            },
                        )
                    },
                },
            },
        },
        emailVerification: {
            sendVerificationEmail: async ({ user, url }) => {
                await sendVerificationEmail(requireRunMutationCtx(ctx), {
                    to: user.email,
                    name: user.name ?? null,
                    url: withWebCallback(url, '/verify-email'),
                })
            },
            sendOnSignUp: true,
            // A blocked sign-in with an unverified email re-sends the link,
            // which is the recovery path for pre-existing unverified users.
            sendOnSignIn: true,
            expiresIn: 60 * 60 * 24,
        },
        rateLimit: {
            enabled: true,
            // better-auth defaults to in-memory storage, which is useless
            // across Convex's stateless isolates.
            storage: 'database',
            customRules: {
                '/request-password-reset': { window: 60, max: 3 },
                '/send-verification-email': { window: 60, max: 3 },
            },
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
