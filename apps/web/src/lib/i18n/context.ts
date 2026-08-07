import { createContext } from 'react'
import type { Messages } from './es'
import type { LanguagePreference, Locale } from './locale'

export type I18nContextValue = {
    /** Messages for the active locale. */
    t: Messages
    /** Which catalog is active. */
    locale: Locale
    /** BCP 47 tag for `Intl.*`; follows the browser under `system`. */
    formatLocale: string
    /** What the user picked in the language menu. */
    preference: LanguagePreference
    setPreference: (preference: LanguagePreference) => void
}

export const I18nContext = createContext<I18nContextValue | null>(null)
