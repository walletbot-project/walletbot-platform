import { useContext } from 'react'
import { I18nContext, type I18nContextValue } from './context'
import type { Messages } from './es'

export { I18nContext, type I18nContextValue } from './context'
export { en } from './en'
export { es, type Messages } from './es'
export {
    formatLocaleFor,
    type LanguagePreference,
    LOCALES,
    type Locale,
    readLanguagePreference,
    readSystemLocaleTag,
    resolveLocale,
    writeLanguagePreference,
} from './locale'

/** Full i18n context. Throws if used outside `I18nProvider`. */
export function useI18n(): I18nContextValue {
    const ctx = useContext(I18nContext)
    if (!ctx) {
        throw new Error('useI18n must be used within an I18nProvider')
    }
    return ctx
}

/** Messages for the active locale: `const t = useT()` → `t.common.save`. */
export function useT(): Messages {
    return useI18n().t
}

/**
 * BCP 47 tag to hand to `Intl.NumberFormat` / `Intl.DateTimeFormat` and to the
 * `locale`-taking helpers in `@/lib/money`.
 */
export function useFormatLocale(): string {
    return useI18n().formatLocale
}
