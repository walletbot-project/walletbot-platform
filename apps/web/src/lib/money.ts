// Money helpers mirroring the native app (apps/native/lib/shared/money.dart).
// Amounts are stored as int64 cents; the UI renders decimal currency using the
// active locale's separators, so `ARS 12.345,67` in es-AR and `ARS 12,345.67`
// in en-US.

/** Prefix for an ISO currency: a symbol for EUR/GBP, the ISO code otherwise. */
export function currencyPrefix(code: string): string {
    switch (code) {
        case 'EUR':
            return '€'
        case 'GBP':
            return '£'
        default:
            return `${code} `
    }
}

/**
 * Formats signed cents as currency, e.g. `1234567` + `ARS` → `ARS 12.345,67`.
 * `locale` is a BCP 47 tag — pass `useFormatLocale()` from a component.
 */
export function formatMoney(
    cents: number,
    currency: string,
    locale?: string,
): string {
    const value = cents / 100
    const formatted = new Intl.NumberFormat(locale, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    }).format(Math.abs(value))
    const sign = cents < 0 ? '-' : ''
    return `${sign}${currencyPrefix(currency)}${formatted}`
}
