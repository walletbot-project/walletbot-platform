import { en } from './en'
import { es, type Messages } from './es'
import { type Locale, resolveLocale } from './locales'

export type { Messages } from './es'
export {
    DEFAULT_LOCALE,
    LOCALE_LABELS,
    LOCALES,
    type Locale,
    resolveLocale,
} from './locales'

// Both catalogs are imported statically: two locales of a handful of short
// strings cost far less than the async boundary a dynamic import would add, and
// the pages are prerendered anyway so nothing ships to the browser.
const CATALOGS: Record<Locale, Messages> = { en, es }

/**
 * Messages for the locale Astro resolved for the route being rendered:
 * `const { locale, t } = useTranslations(Astro.currentLocale)`.
 *
 * Astro's i18n routing decides *which* locale a URL belongs to; this only maps
 * that decision onto a catalog.
 */
export function useTranslations(currentLocale: string | undefined): {
    locale: Locale
    t: Messages
} {
    const locale = resolveLocale(currentLocale)
    return { locale, t: CATALOGS[locale] }
}
