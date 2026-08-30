import { createClient, type GenericCtx } from '@convex-dev/better-auth'
import { convex, crossDomain } from '@convex-dev/better-auth/plugins'
import { requireRunMutationCtx } from '@convex-dev/better-auth/utils'
import { type Locale, resolveLocale } from '@wallet-bot/shared'
import { betterAuth } from 'better-auth/minimal'
import { bearer } from 'better-auth/plugins'
import { components, internal } from './_generated/api'
import type { DataModel } from './_generated/dataModel'
import authConfig from './auth.config'
import {
    outboundLocaleForUser,
    sendResetPasswordEmail,
    sendVerificationEmail,
} from './emails/helpers'

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

const authMethodForWebSession = (
    context: { path?: string; request?: Request } | null,
): 'email_password' | 'google' | null => {
    if (!context) return null
    if (
        context.request?.headers.get('x-walletbot-client-platform') === 'native'
    ) {
        return null
    }
    if (context.path === '/sign-in/email') return 'email_password'
    if (context.path === '/callback/:id') return 'google'
    return null
}

/**
 * `acceptLanguage` is the calling client's language tag, for the flows where
 * better-auth cannot tell us itself. Web goes through the mounted HTTP handler,
 * so the email callbacks below get a real `Request` and read the header off it.
 * Native calls `auth.api.*` directly through `authNative/http.ts`, where there
 * is no such request, so that module reads the header off the incoming native
 * request and passes it here instead.
 *
 * Only ever a fallback: a user with a stored `userSettings.language` gets that,
 * whichever client is asking. See `resolveOutboundLocale`.
 */
export const createAuth = (
    ctx: GenericCtx<DataModel>,
    options?: { acceptLanguage?: string | null },
) => {
    const hintTag = options?.acceptLanguage ?? null
    const localeHint: Locale | null = hintTag ? resolveLocale(hintTag) : null
    return betterAuth({
        baseURL: convexSiteUrl,
        trustedOrigins: [siteUrl, 'flutter://'],
        database: authComponent.adapter(ctx),
        emailAndPassword: {
            enabled: true,
            requireEmailVerification: true,
            sendResetPassword: async ({ user, url }, request) => {
                const runCtx = requireRunMutationCtx(ctx)
                await sendResetPasswordEmail(runCtx, {
                    to: user.email,
                    name: user.name ?? null,
                    url: withWebCallback(url, '/reset-password'),
                    locale: await outboundLocaleForUser(runCtx, {
                        userId: user.id,
                        hint: localeHint,
                        request,
                    }),
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
                        // Seeding the language runs for EVERY newly inserted
                        // user, not just the email path: it is the only way the
                        // verification email sent later in this same request
                        // can be in the right language, since the client has no
                        // session yet to push with. A `device` report, so the
                        // user's first explicit pick replaces it.
                        //
                        // Skipped entirely when neither the request nor the
                        // caller offers a tag. Seeding a guess would be worse
                        // than leaving the field unset: unset falls back to
                        // DEFAULT_LOCALE, which is what these emails already
                        // were, and it lets the client's first report win.
                        const acceptLanguage =
                            context?.request?.headers.get('accept-language') ??
                            hintTag
                        if (acceptLanguage !== null) {
                            await requireRunMutationCtx(ctx).runMutation(
                                internal.v1.users.internal.seedLanguage,
                                { userId: user.id, acceptLanguage },
                            )
                        }

                        if (context?.path !== '/sign-up/email') return
                        await requireRunMutationCtx(ctx).runMutation(
                            internal.telemetry.mutations
                                .recordUserAccountCreated,
                            {
                                userId: user.id,
                                authMethod: 'email_password',
                            },
                        )
                    },
                },
            },
            session: {
                create: {
                    after: async (session, context) => {
                        const authMethod = authMethodForWebSession(context)
                        if (!authMethod) return
                        await requireRunMutationCtx(ctx).runMutation(
                            internal.telemetry.mutations
                                .recordUserAccountSignedIn,
                            {
                                userId: session.userId,
                                authMethod,
                                clientPlatform: 'web',
                            },
                        )
                    },
                },
            },
        },
        emailVerification: {
            sendVerificationEmail: async ({ user, url }, request) => {
                const runCtx = requireRunMutationCtx(ctx)
                await sendVerificationEmail(runCtx, {
                    to: user.email,
                    name: user.name ?? null,
                    url: withWebCallback(url, '/verify-email'),
                    locale: await outboundLocaleForUser(runCtx, {
                        userId: user.id,
                        hint: localeHint,
                        request,
                    }),
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
