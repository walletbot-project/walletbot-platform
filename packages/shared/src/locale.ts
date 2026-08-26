/**
 * The locales the product ships, and the single rule for mapping an arbitrary
 * BCP 47 tag onto one of them.
 *
 * Every layer used to carry its own copy of this: the web catalog picker
 * (`apps/web/src/lib/i18n/locale.ts`), the native config banners
 * (`packages/backend/convex/config/helpers.ts`) and the legal document URLs
 * (`legal.ts`). They now all alias these, so adding a third locale is one edit
 * here plus the catalogs themselves.
 *
 * `DEFAULT_LOCALE` is the answer when there is no tag to resolve at all. It is
 * deliberately NOT the fallback for an unrecognized tag. That is `en`, see
 * `resolveLocale`.
 */

export const LOCALES = ['es', 'en'] as const

export type Locale = (typeof LOCALES)[number]

export const DEFAULT_LOCALE: Locale = 'es'

export const isLocale = (value: string): value is Locale =>
    (LOCALES as readonly string[]).includes(value)

/**
 * Maps a BCP 47 tag (`es`, `es-AR`, `en_US`, `pt-BR`) to a shipped locale.
 * Anything that isn't Spanish falls back to English, which is also what an
 * `Accept-Language` header we can't parse resolves to.
 *
 * Callers with NO tag at all (an unauthenticated request with no header, a
 * user row predating the language field) want `DEFAULT_LOCALE` instead. This
 * function answers `en` for `undefined`, which is the right answer for "the
 * client told us something we don't ship" and the wrong one for "the client
 * told us nothing".
 */
export function resolveLocale(tag: string | undefined | null): Locale {
    return tag?.trim().toLowerCase().replace('_', '-').startsWith('es')
        ? 'es'
        : 'en'
}

/**
 * The single most-preferred tag out of an `Accept-Language` header
 * (`es-AR,es;q=0.9,en;q=0.8` -> `es-AR`), or `null` if there isn't one.
 *
 * `resolveLocale` reads the whole header fine, but a header is not a locale:
 * this is for the places that *store* the tag, where keeping the q-value list
 * around would make the column meaningless.
 */
export function firstLanguageTag(
    acceptLanguage: string | undefined | null,
): string | null {
    const first = acceptLanguage?.split(',')[0]?.split(';')[0]?.trim()
    return first ? first : null
}

/**
 * The longest tag worth storing. BCP 47's own registry keeps well-formed tags
 * far shorter than this; the cap is only here so an untrusted client can't turn
 * the column into free storage.
 */
export const MAX_LOCALE_TAG_LENGTH = 35
