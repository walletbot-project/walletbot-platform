// Exchange-rate resolution for the `getExchangeRate` tool.
//
// The native (Dart) side mirrors this in apps/native/lib/voice/tool_fx.dart;
// parity is locked by fx-fixtures.json (packages/shared/test/fx-fixtures.test.ts
// and apps/native/test/voice/fx_fixtures_test.dart run the same table).
//
// Both executors work off a *snapshot*: the list of quotes the backend
// refreshes from its providers (packages/backend/convex/exchangeRates). No
// executor ever calls a provider itself — web reads the snapshot through a
// Convex query, native through a device-scoped cached fetch, so the tool stays
// instant and works from cache when the network is down.
//
// Semantics (identical on both platforms):
// - A quote reads "1 base = rate quote". `buy`/`sell` are the provider's
//   compra/venta when it publishes both, and only survive a direct hit.
// - A pair is resolved direct, then inverted, then triangulated through USD.
// - A market the pair has no quote for falls back to `official`, and the
//   resolution reports the market actually used.
// - Nothing here converts stored money: balances and summaries always stay in
//   their account's currency.

/**
 * The quote flavors a pair can carry. Only ARS pairs currently have more than
 * `official` — the Argentine market publishes several simultaneous prices for
 * the same pair (see the `exchange-rates` agent skill).
 */
export const FX_MARKETS = [
    'official',
    'blue',
    'mep',
    'ccl',
    'card',
    'crypto',
    'wholesale',
] as const

export type FxMarket = (typeof FX_MARKETS)[number]

/** Used whenever the caller names no market, and the fallback for every pair. */
export const DEFAULT_FX_MARKET: FxMarket = 'official'

/**
 * A quote older than this is reported as `stale`. Sized to cover a long
 * weekend: markets legitimately do not move Friday close → Monday open, and
 * flagging that as stale every Monday would be noise, not information.
 */
export const FX_STALE_AFTER_MS = 72 * 60 * 60 * 1000

/** One cached quote: 1 `base` = `rate` `quote`. */
export type FxQuote = {
    base: string
    quote: string
    market: FxMarket
    rate: number
    /** Provider's compra, when it publishes a two-sided price. */
    buy?: number
    /** Provider's venta, when it publishes a two-sided price. */
    sell?: number
    source: string
    /** ISO 8601 timestamp of the provider's own "last updated". */
    asOf: string
}

export type FxPath = 'direct' | 'inverse' | 'triangulated'

export type FxResolution = {
    from: string
    to: string
    /** The market actually used, which may differ from the one requested. */
    market: FxMarket
    rate: number
    buy?: number
    sell?: number
    source: string
    asOf: string
    path: FxPath
}

const USD = 'USD'

export function normalizeCurrencyCode(code: string): string {
    return code.trim().toUpperCase()
}

export function isFxMarket(value: string): value is FxMarket {
    return (FX_MARKETS as readonly string[]).includes(value)
}

function olderOf(left: string, right: string): string {
    const leftMs = Date.parse(left)
    const rightMs = Date.parse(right)
    if (Number.isNaN(leftMs)) return Number.isNaN(rightMs) ? left : right
    if (Number.isNaN(rightMs)) return left
    return leftMs <= rightMs ? left : right
}

function joinSources(left: string, right: string): string {
    return left === right ? left : `${left}+${right}`
}

function findQuote(
    snapshot: readonly FxQuote[],
    base: string,
    quote: string,
    market: FxMarket,
): FxQuote | undefined {
    return snapshot.find(
        (entry) =>
            entry.base === base &&
            entry.quote === quote &&
            entry.market === market,
    )
}

type Leg = { rate: number; asOf: string; source: string; market: FxMarket }

/**
 * One side of a triangulation: USD → `code`, at `market` or else official.
 *
 * There is deliberately no USD identity case. A pair with USD on one side is
 * exactly the lookup the direct/inverse pass already made, so triangulating it
 * could never find anything that pass missed — and a synthetic USD leg would
 * need a fake `asOf` that would then poison the resolution's timestamp.
 */
function usdLeg(
    snapshot: readonly FxQuote[],
    code: string,
    market: FxMarket,
): Leg | undefined {
    for (const candidate of marketChain(market)) {
        const direct = findQuote(snapshot, USD, code, candidate)
        if (direct) {
            return {
                rate: direct.rate,
                asOf: direct.asOf,
                source: direct.source,
                market: candidate,
            }
        }
        const inverse = findQuote(snapshot, code, USD, candidate)
        if (inverse && inverse.rate > 0) {
            return {
                rate: 1 / inverse.rate,
                asOf: inverse.asOf,
                source: inverse.source,
                market: candidate,
            }
        }
    }
    return undefined
}

/** The requested market first, then the official fallback (deduped). */
function marketChain(market: FxMarket): FxMarket[] {
    return market === DEFAULT_FX_MARKET ? [market] : [market, DEFAULT_FX_MARKET]
}

/**
 * Resolves `from` → `to` against a snapshot, preferring `market`. Returns null
 * when neither a direct, inverse nor USD-triangulated path exists.
 */
export function resolveFxQuote(
    snapshot: readonly FxQuote[],
    fromCode: string,
    toCode: string,
    market: FxMarket = DEFAULT_FX_MARKET,
): FxResolution | null {
    const from = normalizeCurrencyCode(fromCode)
    const to = normalizeCurrencyCode(toCode)

    for (const candidate of marketChain(market)) {
        const direct = findQuote(snapshot, from, to, candidate)
        if (direct) {
            return {
                from,
                to,
                market: candidate,
                rate: direct.rate,
                buy: direct.buy,
                sell: direct.sell,
                source: direct.source,
                asOf: direct.asOf,
                path: 'direct',
            }
        }
        const inverse = findQuote(snapshot, to, from, candidate)
        if (inverse && inverse.rate > 0) {
            return {
                from,
                to,
                market: candidate,
                // buy/sell are dropped: inverting a two-sided price also swaps
                // the sides, which is a subtlety the model should not have to
                // reason about. The mid rate is unambiguous.
                rate: 1 / inverse.rate,
                source: inverse.source,
                asOf: inverse.asOf,
                path: 'inverse',
            }
        }
    }

    const fromLeg = usdLeg(snapshot, from, market)
    const toLeg = usdLeg(snapshot, to, market)
    if (!fromLeg || !toLeg || fromLeg.rate <= 0) return null
    return {
        from,
        to,
        // The requested market survives only if a leg actually carried it.
        market:
            fromLeg.market === market || toLeg.market === market
                ? market
                : DEFAULT_FX_MARKET,
        rate: toLeg.rate / fromLeg.rate,
        source: joinSources(fromLeg.source, toLeg.source),
        asOf: olderOf(fromLeg.asOf, toLeg.asOf),
        path: 'triangulated',
    }
}

/**
 * Every market this exact pair is quoted in (direct or inverted), so the agent
 * can say "oficial 1530, blue 1565" without a second call. Empty unless the
 * pair carries more than one market.
 */
export function fxAlternatives(
    snapshot: readonly FxQuote[],
    fromCode: string,
    toCode: string,
): Partial<Record<FxMarket, number>> {
    const from = normalizeCurrencyCode(fromCode)
    const to = normalizeCurrencyCode(toCode)
    const result: Partial<Record<FxMarket, number>> = {}
    for (const market of FX_MARKETS) {
        const direct = findQuote(snapshot, from, to, market)
        if (direct) {
            result[market] = direct.rate
            continue
        }
        const inverse = findQuote(snapshot, to, from, market)
        if (inverse && inverse.rate > 0) result[market] = 1 / inverse.rate
    }
    return Object.keys(result).length > 1 ? result : {}
}

/** Half away from zero, matching Dart's `num.round()`. */
function roundTo(value: number, digits: number): number {
    if (!Number.isFinite(value)) return value
    const factor = 10 ** digits
    const scaled = value * factor
    const rounded = scaled < 0 ? -Math.round(-scaled) : Math.round(scaled)
    return rounded / factor
}

/** Converts a display-unit amount at `rate`, rounded to 2 decimals. */
export function convertAmount(amount: number, rate: number): number {
    return roundTo(amount * rate, 2)
}

export function isFxQuoteStale(asOf: string, nowMs: number): boolean {
    const parsed = Date.parse(asOf)
    if (Number.isNaN(parsed)) return true
    return nowMs - parsed > FX_STALE_AFTER_MS
}
