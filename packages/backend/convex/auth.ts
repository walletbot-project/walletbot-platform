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

export const createAuth = (ctx: GenericCtx<DataModel>) => {
    return betterAuth({
        baseURL: convexSiteUrl,
        trustedOrigins: [siteUrl, 'flutter://'],
        database: authComponent.adapter(ctx),
        user: {
            additionalFields: {
                // Legal-documents version the client showed at sign-up.
                // Carried through /sign-up/email so the create hook below can
                // record the acceptance against the real user insert; the
                // canonical record lives in the `termsAcceptances` table.
                termsAcceptedVersion: {
                    type: 'string',
                    required: false,
                },
            },
        },
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
                    // Scoped to the email path: social sign-in creates users
                    // through `/sign-in/social`, and `googleSignIn` in
                    // `authNative/http.ts` already records those.
                    after: async (user, context) => {
                        if (context?.path !== '/sign-up/email') return
                        await requireRunMutationCtx(ctx).runMutation(
                            internal.telemetry.mutations
                                .recordUserAccountCreated,
                            {
                                userId: user.id,
                                authMethod: 'email_password',
                            },
                        )
                        // Terms acceptance ticked on the sign-up form (web
                        // client and the native /auth/email/sign-up endpoint
                        // both pass it through the sign-up body). Recording
                        // hangs off the real insert for the same reason as
                        // the telemetry above; accounts created without it
                        // are re-prompted by the post-auth gate.
                        const termsAcceptedVersion = user.termsAcceptedVersion
                        if (
                            typeof termsAcceptedVersion === 'string' &&
                            termsAcceptedVersion.length > 0
                        ) {
                            await requireRunMutationCtx(ctx).runMutation(
                                internal.legal.internal.recordSignupAcceptance,
                                {
                                    userId: user.id,
                                    documentVersion: termsAcceptedVersion,
                                },
                            )
                        }
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
