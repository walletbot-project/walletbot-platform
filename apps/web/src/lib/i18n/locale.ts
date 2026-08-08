/** Locales the web app ships a message catalog for. */
export const LOCALES = ['es', 'en'] as const

export type Locale = (typeof LOCALES)[number]

/**
 * What the user picked in the language menu. `system` defers to the browser,
 * mirroring the native app's `DisplayLanguage` tri-state
 * (apps/native/lib/settings/display_settings.dart).
 */
export type LanguagePreference = 'system' | Locale

/**
 * Device-scoped, so it deliberately does not follow the account: the key name
 * matches the native app's SharedPreferences entry.
 */
const STORAGE_KEY = 'display_language'

const isLocale = (value: string): value is Locale =>
    LOCALES.some((locale) => locale === value)

/**
 * Maps a BCP 47 tag to a supported locale. Anything that isn't Spanish falls
 * back to English — the same rule the backend applies in `resolveConfigLocale`
 * (packages/backend/convex/config/helpers.ts).
 */
export function resolveLocale(tag: string | undefined): Locale {
    return tag?.trim().toLowerCase().replace('_', '-').startsWith('es')
        ? 'es'
        : 'en'
}

/** The browser's preferred BCP 47 tag, e.g. `es-AR`. */
export function readSystemLocaleTag(): string {
    return navigator.language
}

/**
 * The tag handed to `Intl.*`. Under `system` it is the browser's full tag so a
 * user keeps their regional number and date formats even when the catalog
 * falls back to English.
 */
export function formatLocaleFor(
    preference: LanguagePreference,
    systemTag: string,
): string {
    return preference === 'system' ? systemTag : preference
}

export function readLanguagePreference(): LanguagePreference {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored === null) return 'system'
    if (stored === 'system' || isLocale(stored)) return stored
    return 'system'
}

export function writeLanguagePreference(preference: LanguagePreference): void {
    if (preference === 'system') {
        localStorage.removeItem(STORAGE_KEY)
        return
    }
    localStorage.setItem(STORAGE_KEY, preference)
}
