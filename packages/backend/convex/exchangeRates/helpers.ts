import { type FxQuote, isFxMarket } from '@wallet-bot/shared'
import type { QueryCtx } from '../_generated/server'
import { SNAPSHOT_BASES } from './utils'

/**
 * The whole rate snapshot, in the wire shape both agent executors resolve
 * against (`resolveFxQuote` in `@wallet-bot/shared`).
 *
 * Read as one indexed range per base rather than a table scan. The set of
 * bases is fixed — `upsertRates` rejects anything outside `SNAPSHOT_BASES` —
 * so this is bounded at roughly the currency catalog's size and cannot grow
 * with users or time.
 */
export async function readSnapshot(ctx: QueryCtx): Promise<FxQuote[]> {
    const quotes: FxQuote[] = []
    for (const base of SNAPSHOT_BASES) {
        const rows = await ctx.db
            .query('exchangeRates')
            .withIndex('by_pair_market', (q) => q.eq('base', base))
            .collect()
        for (const row of rows) {
            if (!isFxMarket(row.market)) continue
            quotes.push({
                base: row.base,
                quote: row.quote,
                market: row.market,
                rate: row.rate,
                buy: row.buy,
                sell: row.sell,
                source: row.source,
                asOf: new Date(Number(row.asOf)).toISOString(),
            })
        }
    }
    return quotes
}
