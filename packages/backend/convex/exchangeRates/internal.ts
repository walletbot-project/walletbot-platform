import { isFxMarket } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internal } from '../_generated/api'
import {
    internalAction,
    internalMutation,
    internalQuery,
} from '../_generated/server'
import { readSnapshot } from './helpers'
import {
    DOLARAPI_COTIZACIONES_URL,
    DOLARAPI_DOLARES_URL,
    DOLARAPI_SOURCE,
    FRANKFURTER_RATES_URL,
    FRANKFURTER_SOURCE,
    type ParsedRate,
    parseDolarApi,
    parseFrankfurter,
    SNAPSHOT_BASES,
    sourcePriority,
} from './utils'

// Refresh + read internals for the exchange-rate cache. Deliberately not
// 'use node': the default runtime has fetch, which is all these need.
//
// The runtime has no AbortController/AbortSignal (see Convex's supported-APIs
// list), so there is no per-request timeout here; a hung provider is bounded
// by the action's own execution limit and the next cron tick simply retries.
// Every failure path leaves the previous rows untouched — a stale quote with
// an honest `asOf` beats no quote at all.

/**
 * How long a higher-priority source's row is protected from being overwritten
 * by a lower-priority one. Past this, a stale row is worse than a fallback.
 */
const SOURCE_TAKEOVER_AFTER_MS = 24 * 60 * 60 * 1000

/** What both refresh actions report back, annotated so the self-referential
 * `internal.exchangeRates.internal.upsertRates` call in the same file does not
 * make their return type circular. */
type RefreshResult = { written: number; skipped: number }

const rateValidator = v.object({
    base: v.string(),
    quote: v.string(),
    market: v.string(),
    rate: v.number(),
    buy: v.optional(v.number()),
    sell: v.optional(v.number()),
    asOf: v.number(),
})

export const upsertRates = internalMutation({
    args: { source: v.string(), rates: v.array(rateValidator) },
    handler: async (ctx, args) => {
        const now = Date.now()
        let written = 0
        let skipped = 0
        for (const rate of args.rates) {
            if (
                !SNAPSHOT_BASES.includes(rate.base) ||
                !isFxMarket(rate.market)
            ) {
                skipped += 1
                continue
            }
            const existing = await ctx.db
                .query('exchangeRates')
                .withIndex('by_pair_market', (q) =>
                    q
                        .eq('base', rate.base)
                        .eq('quote', rate.quote)
                        .eq('market', rate.market),
                )
                .unique()
            const defended =
                existing !== null &&
                sourcePriority(existing.source) > sourcePriority(args.source) &&
                now - Number(existing.fetchedAt) < SOURCE_TAKEOVER_AFTER_MS
            if (defended) {
                skipped += 1
                continue
            }
            const doc = {
                base: rate.base,
                quote: rate.quote,
                market: rate.market,
                rate: rate.rate,
                buy: rate.buy,
                sell: rate.sell,
                source: args.source,
                asOf: BigInt(Math.trunc(rate.asOf)),
                fetchedAt: BigInt(now),
            }
            if (existing) await ctx.db.replace(existing._id, doc)
            else await ctx.db.insert('exchangeRates', doc)
            written += 1
        }
        return { written, skipped }
    },
})

async function fetchJson(url: string): Promise<unknown | null> {
    try {
        const response = await fetch(url, {
            headers: { accept: 'application/json' },
        })
        if (!response.ok) {
            console.error(`[fx] ${url} responded ${response.status}`)
            return null
        }
        return await response.json()
    } catch (error) {
        console.error(`[fx] ${url} failed: ${String(error)}`)
        return null
    }
}

export const refreshArgentineRates = internalAction({
    args: {},
    handler: async (ctx): Promise<RefreshResult> => {
        const rates: ParsedRate[] = []
        for (const url of [DOLARAPI_DOLARES_URL, DOLARAPI_COTIZACIONES_URL]) {
            const payload = await fetchJson(url)
            if (payload !== null) rates.push(...parseDolarApi(payload))
        }
        if (rates.length === 0) {
            console.error('[fx] argentine refresh produced no usable rates')
            return { written: 0, skipped: 0 }
        }
        return await ctx.runMutation(
            internal.exchangeRates.internal.upsertRates,
            { source: DOLARAPI_SOURCE, rates },
        )
    },
})

export const refreshInternationalRates = internalAction({
    args: {},
    handler: async (ctx): Promise<RefreshResult> => {
        const payload = await fetchJson(FRANKFURTER_RATES_URL)
        const rates = payload === null ? [] : parseFrankfurter(payload)
        if (rates.length === 0) {
            console.error('[fx] international refresh produced no usable rates')
            return { written: 0, skipped: 0 }
        }
        return await ctx.runMutation(
            internal.exchangeRates.internal.upsertRates,
            { source: FRANKFURTER_SOURCE, rates },
        )
    },
})

/** The snapshot for the unauthenticated `GET /v1/fx/rates` httpAction. */
export const snapshot = internalQuery({
    args: {},
    handler: async (ctx) => await readSnapshot(ctx),
})
