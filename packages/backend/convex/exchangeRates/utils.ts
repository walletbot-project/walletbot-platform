import {
    type FxMarket,
    isValidCurrencyCode,
    normalizeCurrencyCode,
} from '@wallet-bot/shared'

// Provider adapters for the exchange-rate refresh. Pure functions over the
// decoded JSON so they can be unit-tested without touching the network:
// anything malformed is dropped rather than throwing, because one bad row
// from a provider must never abort a whole refresh.

export type ParsedRate = {
    base: string
    quote: string
    market: FxMarket
    rate: number
    buy?: number
    sell?: number
    /** The provider's own "last updated" instant, ms epoch. */
    asOf: number
}

export const DOLARAPI_SOURCE = 'dolarapi'
export const FRANKFURTER_SOURCE = 'frankfurter'

/** USD quoted against ARS in each Argentine market. */
export const DOLARAPI_DOLARES_URL = 'https://dolarapi.com/v1/dolares'
/** EUR/BRL/CLP/UYU quoted against ARS, official market only. */
export const DOLARAPI_COTIZACIONES_URL = 'https://dolarapi.com/v1/cotizaciones'
/** Every currency quoted against USD, from central-bank reference rates. */
export const FRANKFURTER_RATES_URL =
    'https://api.frankfurter.dev/v2/rates?base=USD'

/**
 * Ranking used when two providers cover the same pair. A lower-priority
 * source may still fill a gap, but never overwrites a fresh row written by a
 * higher-priority one — see `internal.ts`. dolarapi wins for ARS because it
 * publishes the Argentine market prices with both sides; frankfurter is the
 * fallback that keeps USD→ARS answerable if dolarapi is down on a cold start.
 */
export const SOURCE_PRIORITY: Readonly<Record<string, number>> = {
    [DOLARAPI_SOURCE]: 2,
    [FRANKFURTER_SOURCE]: 1,
}

/**
 * The only bases the cache stores, and therefore the only ones
 * `readSnapshot` reads back: USD (frankfurter, plus every Argentine market
 * for USD→ARS) and the four currencies dolarapi quotes directly against ARS.
 * `upsertRates` rejects anything else, which is what keeps the table bounded
 * and the per-base indexed reads exhaustive.
 */
export const SNAPSHOT_BASES: readonly string[] = [
    'USD',
    'EUR',
    'BRL',
    'CLP',
    'UYU',
]

export function sourcePriority(source: string): number {
    return SOURCE_PRIORITY[source] ?? 0
}

const CASA_TO_MARKET: Readonly<Record<string, FxMarket>> = {
    oficial: 'official',
    blue: 'blue',
    bolsa: 'mep',
    contadoconliqui: 'ccl',
    tarjeta: 'card',
    cripto: 'crypto',
    mayorista: 'wholesale',
}

function asRecord(value: unknown): Record<string, unknown> | null {
    return typeof value === 'object' && value !== null && !Array.isArray(value)
        ? (value as Record<string, unknown>)
        : null
}

function asPositiveNumber(value: unknown): number | undefined {
    return typeof value === 'number' && Number.isFinite(value) && value > 0
        ? value
        : undefined
}

function asTimestamp(value: unknown): number | undefined {
    if (typeof value !== 'string') return undefined
    const parsed = Date.parse(value)
    return Number.isNaN(parsed) ? undefined : parsed
}

function asKnownCurrency(value: unknown): string | undefined {
    if (typeof value !== 'string') return undefined
    const code = normalizeCurrencyCode(value)
    return isValidCurrencyCode(code) ? code : undefined
}

/**
 * The reference rate of a two-sided quote: the midpoint when the provider
 * publishes both sides, otherwise whichever side it published. `buy`/`sell`
 * travel alongside it so the agent can still answer "what would it cost me".
 */
function midRate(
    buy: number | undefined,
    sell: number | undefined,
): number | undefined {
    if (buy !== undefined && sell !== undefined) return (buy + sell) / 2
    return buy ?? sell
}

/**
 * `[{ moneda, casa, compra, venta, fechaActualizacion }]` — used for both
 * `/v1/dolares` (USD in every market) and `/v1/cotizaciones` (other
 * currencies, official only). Everything is quoted against ARS.
 */
export function parseDolarApi(payload: unknown): ParsedRate[] {
    if (!Array.isArray(payload)) return []
    const rates: ParsedRate[] = []
    for (const raw of payload) {
        const entry = asRecord(raw)
        if (!entry) continue
        const base = asKnownCurrency(entry.moneda)
        const market =
            typeof entry.casa === 'string'
                ? CASA_TO_MARKET[entry.casa.toLowerCase()]
                : undefined
        const asOf = asTimestamp(entry.fechaActualizacion)
        if (!base || base === 'ARS' || !market || asOf === undefined) continue
        const buy = asPositiveNumber(entry.compra)
        const sell = asPositiveNumber(entry.venta)
        const rate = midRate(buy, sell)
        if (rate === undefined) continue
        rates.push({ base, quote: 'ARS', market, rate, buy, sell, asOf })
    }
    return rates
}

/**
 * `[{ date, base, quote, rate }]` from frankfurter's `/v2/rates?base=USD`.
 * Only currencies in the app's catalog are kept; `date` is a calendar day, so
 * it is anchored at UTC midnight.
 */
export function parseFrankfurter(payload: unknown): ParsedRate[] {
    if (!Array.isArray(payload)) return []
    const rates: ParsedRate[] = []
    for (const raw of payload) {
        const entry = asRecord(raw)
        if (!entry) continue
        const base = asKnownCurrency(entry.base)
        const quote = asKnownCurrency(entry.quote)
        const rate = asPositiveNumber(entry.rate)
        const asOf =
            typeof entry.date === 'string'
                ? asTimestamp(`${entry.date}T00:00:00.000Z`)
                : undefined
        if (!base || !quote || base === quote || rate === undefined) continue
        if (asOf === undefined) continue
        rates.push({ base, quote, market: 'official', rate, asOf })
    }
    return rates
}
