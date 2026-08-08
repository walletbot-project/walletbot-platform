import { CURRENCIES, DEFAULT_CURRENCY, SUGGESTED_CURRENCIES } from '@wallet-bot/shared'

// Currency codes, sourced from the shared catalog (single source of truth for
// backend validation and both clients).
export const CURRENCY_CODES: readonly string[] = CURRENCIES.map((c) => c.code)

/**
 * Localized currency name, e.g. `ARS` → `peso argentino` (es) /
 * `Argentine Peso` (en). Falls back to the ISO code when the runtime has no
 * display name for it.
 */
export function currencyName(code: string, locale?: string): string {
    const names = new Intl.DisplayNames([locale ?? 'en'], { type: 'currency' })
    return names.of(code) ?? code
}

export { DEFAULT_CURRENCY, SUGGESTED_CURRENCIES }
