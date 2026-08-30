import { DEFAULT_LOCALE, type Locale, resolveLocale } from '@wallet-bot/shared'

/**
 * Which language an outbound message goes out in, best signal first:
 *
 * 1. `stored`, the `userSettings.language` the user's clients reported.
 * 2. `hint`, a locale the caller knows out of band. Native auth requests
 *    carry one (`authNative/http.ts` reads `Accept-Language` off the incoming
 *    request and passes it to `createAuth`), because better-auth's own
 *    `request` is undefined for the direct `auth.api.*` calls native makes.
 * 3. `acceptLanguage`, the header on a real HTTP request, which is what the
 *    web sign-up and password-reset flows have.
 * 4. `DEFAULT_LOCALE`, for no signal at all. Spanish, which is what every one
 *    of these emails was before it could be localized, so a user with no
 *    stored language sees no change.
 *
 * Note the difference between 3 and 4: `resolveLocale` answers `en` for a tag
 * it doesn't ship, which is right for "the client asked for Portuguese" and
 * wrong for "nobody said anything".
 */
export const resolveOutboundLocale = (args: {
    stored?: Locale | null
    hint?: Locale | null
    acceptLanguage?: string | null
}): Locale => {
    if (args.stored) return args.stored
    if (args.hint) return args.hint
    if (args.acceptLanguage) return resolveLocale(args.acceptLanguage)
    return DEFAULT_LOCALE
}
