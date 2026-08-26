import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// Market exchange rates, refreshed from public providers by the crons in
// crons.ts. Global data, not user data: there is no `userId` and no sync —
// the agent's `getExchangeRate` tool reads a snapshot of this table (web
// through v1/exchangeRates/queries, native through GET /v1/fx/rates).
//
// The row set is bounded and constant by construction: one row per
// (base, quote, market) the refresh writes, and the refresh only ever writes
// pairs whose codes are in `@wallet-bot/shared`'s CURRENCIES catalog. Reads
// are per-base index scans, never table scans.
export const exchangeRates = defineTable({
    /** ISO 4217 code the rate is quoted FROM. */
    base: v.string(),
    /** ISO 4217 code the rate is quoted TO: 1 base = rate quote. */
    quote: v.string(),
    /** An `FxMarket` value from `@wallet-bot/shared`. */
    market: v.string(),
    rate: v.number(),
    /** Provider's compra, when it publishes a two-sided price. */
    buy: v.optional(v.number()),
    /** Provider's venta, when it publishes a two-sided price. */
    sell: v.optional(v.number()),
    /** Which provider produced the row, e.g. 'dolarapi'. */
    source: v.string(),
    /** The provider's own "last updated" instant, ms epoch. */
    asOf: v.int64(),
    /** When we last wrote this row, ms epoch. */
    fetchedAt: v.int64(),
}).index('by_pair_market', ['base', 'quote', 'market'])
