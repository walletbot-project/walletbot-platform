// The TS half of the cross-language exchange-rate parity suite. The same
// fixture table runs against the Dart mirrors in
// apps/native/test/voice/fx_fixtures_test.dart — a behavioural change on one
// side fails the other side's run until both are updated together.

import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import {
    convertAmount,
    type FxMarket,
    type FxQuote,
    type FxResolution,
    fxAlternatives,
    isFxQuoteStale,
    resolveFxQuote,
} from '../src/tools/fx'

type Fixtures = {
    nowMs: number
    snapshot: FxQuote[]
    resolve: {
        from: string
        to: string
        market?: FxMarket
        expected: FxResolution | null
    }[]
    alternatives: {
        from: string
        to: string
        expected: Partial<Record<FxMarket, number>>
    }[]
    convert: { amount: number; rate: number; value: number }[]
    stale: { asOf: string; expected: boolean }[]
}

const fixtures: Fixtures = JSON.parse(
    readFileSync(
        resolve(import.meta.dirname, '../src/tools/fx-fixtures.json'),
        'utf8',
    ),
)

/** Drops the undefined buy/sell keys so `toEqual` matches the fixture rows. */
function compact(resolution: FxResolution | null): unknown {
    if (resolution === null) return null
    return Object.fromEntries(
        Object.entries(resolution).filter(([, value]) => value !== undefined),
    )
}

describe('resolveFxQuote fixtures', () => {
    for (const c of fixtures.resolve) {
        it(`${c.from}->${c.to}${c.market ? ` (${c.market})` : ''}`, () => {
            const result = resolveFxQuote(
                fixtures.snapshot,
                c.from,
                c.to,
                c.market,
            )
            expect(compact(result)).toEqual(c.expected)
        })
    }
})

describe('fxAlternatives fixtures', () => {
    for (const c of fixtures.alternatives) {
        it(`${c.from}->${c.to}`, () => {
            expect(fxAlternatives(fixtures.snapshot, c.from, c.to)).toEqual(
                c.expected,
            )
        })
    }
})

describe('convertAmount fixtures', () => {
    for (const c of fixtures.convert) {
        it(`${c.amount} * ${c.rate}`, () => {
            // Both platforms compute in IEEE 754 doubles and round half away
            // from zero — results are exact, not approximate.
            expect(convertAmount(c.amount, c.rate)).toBe(c.value)
        })
    }
})

describe('isFxQuoteStale fixtures', () => {
    for (const c of fixtures.stale) {
        it(c.asOf, () => {
            expect(isFxQuoteStale(c.asOf, fixtures.nowMs)).toBe(c.expected)
        })
    }
})
