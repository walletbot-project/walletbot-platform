import {
    isLocale,
    LOCALES,
    type Locale,
    resolveLocale,
} from '@wallet-bot/shared'

export { isLocale, LOCALES, type Locale, resolveLocale }

/**
 * What the user picked in the language menu. `system` defers to the browser,
 * mirroring the native app's `DisplayLanguage` tri-state
 * (apps/native/lib/settings/display_settings.dart).
 */
export type LanguagePreference = 'system' | Locale

/**
 * Device-scoped, so it deliberately does not follow the account: the key name
 * matches the native app's SharedPreferences entry.
 *
 * The *server* does hold a per-user language (`userSettings.language`), but it
 * is only ever read for outbound email/WhatsApp — never to drive this display
 * preference. See `useLanguageSync` (hooks/use-language-sync.ts).
 */
const STORAGE_KEY = 'display_language'

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
