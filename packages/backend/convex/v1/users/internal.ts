import { firstLanguageTag, resolveLocale } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internalMutation, internalQuery } from '../../_generated/server'
import { applyLanguageReport, getUserLanguage } from './helpers'

/**
 * The stored language, for callers that only have an action or auth-callback
 * ctx (the better-auth email hooks in `auth.ts`, and `authNative/http.ts`).
 */
export const getLanguage = internalQuery({
    args: { userId: v.string() },
    handler: async (ctx, { userId }) => await getUserLanguage(ctx, userId),
})

/**
 * Seeds the language for a user who cannot call
 * `v1/users/mutations:updateLanguage` yet, which is every brand-new account:
 * the verification email goes out inside the sign-up request, before the
 * client has an authenticated session to push with.
 *
 * Takes the raw `Accept-Language` header, since that is all a sign-up request
 * carries. Always a `device` report, so the user's first explicit pick
 * replaces it.
 */
export const seedLanguage = internalMutation({
    args: { userId: v.string(), acceptLanguage: v.string() },
    handler: async (ctx, args) => {
        const tag = firstLanguageTag(args.acceptLanguage)
        await applyLanguageReport(ctx, args.userId, {
            language: resolveLocale(args.acceptLanguage),
            source: 'device',
            ...(tag === null ? {} : { tag }),
        })
    },
})
