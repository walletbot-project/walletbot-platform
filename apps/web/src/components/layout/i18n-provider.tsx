import { useCallback, useEffect, useMemo, useState } from 'react'
import {
    formatLocaleFor,
    type LanguagePreference,
    type Locale,
    type Messages,
    readLanguagePreference,
    readSystemLocaleTag,
    resolveLocale,
    writeLanguagePreference,
} from '@/lib/i18n'
import { I18nContext } from '@/lib/i18n/context'
import { en } from '@/lib/i18n/en'
import { es } from '@/lib/i18n/es'

// Both catalogs are imported statically: two locales of a few hundred short
// strings cost far less than the loading state a dynamic import would force on
// every first paint and every language switch.
const CATALOGS: Record<Locale, Messages> = { es, en }

export function I18nProvider({ children }: { children: React.ReactNode }) {
    const [preference, setPreferenceState] = useState<LanguagePreference>(
        readLanguagePreference,
    )
    const [systemTag, setSystemTag] = useState(readSystemLocaleTag)

    // The browser can change its preferred language while the app is open —
    // mirrors the native app reacting to `didChangeLocales`.
    useEffect(() => {
        const handleLanguageChange = () => setSystemTag(readSystemLocaleTag())
        window.addEventListener('languagechange', handleLanguageChange)
        return () =>
            window.removeEventListener('languagechange', handleLanguageChange)
    }, [])

    const setPreference = useCallback((next: LanguagePreference) => {
        writeLanguagePreference(next)
        setPreferenceState(next)
    }, [])

    const value = useMemo(() => {
        const formatLocale = formatLocaleFor(preference, systemTag)
        const locale = resolveLocale(formatLocale)
        return {
            t: CATALOGS[locale],
            locale,
            formatLocale,
            preference,
            setPreference,
        }
    }, [preference, systemTag, setPreference])

    useEffect(() => {
        document.documentElement.lang = value.locale
    }, [value.locale])

    return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}
