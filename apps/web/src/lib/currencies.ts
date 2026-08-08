// Currency catalog mirrored from the native create-account screen
// (apps/native/lib/screens/create_account.dart), sorted alphabetically by ISO
// code. Display names come from `Intl.DisplayNames` so they follow the active
// locale instead of being hardcoded in one language.
export const CURRENCY_CODES: readonly string[] = [
    'AED',
    'ARS',
    'AUD',
    'BOB',
    'BRL',
    'CAD',
    'CHF',
    'CLP',
    'CNY',
    'COP',
    'CRC',
    'CUP',
    'DKK',
    'DOP',
    'EGP',
    'EUR',
    'GBP',
    'GTQ',
    'HKD',
    'HNL',
    'HUF',
    'IDR',
    'ILS',
    'INR',
    'JPY',
    'KRW',
    'MXN',
    'MYR',
    'NGN',
    'NIO',
    'NOK',
    'NZD',
    'PAB',
    'PEN',
    'PHP',
    'PKR',
    'PLN',
    'PYG',
    'RON',
    'RUB',
    'SAR',
    'SEK',
    'SGD',
    'THB',
    'TRY',
    'TWD',
    'UAH',
    'USD',
    'UYU',
    'VES',
    'VND',
    'ZAR',
]

/**
 * Localized currency name, e.g. `ARS` → `peso argentino` (es) /
 * `Argentine Peso` (en). Falls back to the ISO code when the runtime has no
 * display name for it.
 */
export function currencyName(code: string, locale?: string): string {
    const names = new Intl.DisplayNames([locale ?? 'en'], { type: 'currency' })
    return names.of(code) ?? code
}

export const SUGGESTED_CURRENCIES = ['ARS', 'USD', 'EUR', 'BRL'] as const

export const DEFAULT_CURRENCY = 'ARS'
