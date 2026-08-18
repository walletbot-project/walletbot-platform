/**
 * Locales the landing ships a catalog for. Must stay in sync with `i18n.locales`
 * in `astro.config.mjs` — Astro owns the routing, this owns the copy.
 */
export const LOCALES = ['en', 'es'] as const

export type Locale = (typeof LOCALES)[number]

/** Must stay in sync with `i18n.defaultLocale` in `astro.config.mjs`. */
export const DEFAULT_LOCALE: Locale = 'en'

/** Each language named in itself, for the language switcher. */
export const LOCALE_LABELS: Record<Locale, string> = {
    en: 'English',
    es: 'Español',
}

/**
 * Whether a raw string is one of the locales this site ships. Exported for
 * `functions/index.ts`, which negotiates `Accept-Language` tags at the edge and
 * needs to narrow them without falling back to the default.
 */
export const isLocale = (value: string): value is Locale =>
    LOCALES.some((locale) => locale === value)

/**
 * Narrows `Astro.currentLocale`, which is typed `string | undefined` because
 * Astro cannot prove at the type level that the rendering route sits under one
 * of the configured locales. Anything unexpected falls back to the default,
 * matching `resolveLocale` in `apps/web/src/lib/i18n/locale.ts`.
 */
export function resolveLocale(value: string | undefined): Locale {
    return value !== undefined && isLocale(value) ? value : DEFAULT_LOCALE
}
