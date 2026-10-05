// The TS half of the cross-language parsing parity suite. The same fixture
// table runs against the Dart mirrors in
// apps/native/test/voice/parsing_fixtures_test.dart — a behavioural change on
// one side fails the other side's run until both are updated together.

import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { pastCutoffMs } from '../src/occurrence'
import {
    balanceAsOfMs,
    parseAmountToCents,
    parseNaturalDate,
    parseTransactionDate,
    type TransactionTimeStatus,
} from '../src/tools/parsing'

type LocalDate = {
    year: number
    month: number
    day: number
    hour?: number
    minute?: number
    second?: number
    millisecond?: number
}

type Fixtures = {
    now: Required<LocalDate>
    amountToCents: { input: number; cents: string }[]
    naturalDate: { input: string; expect?: LocalDate; throws?: boolean }[]
    transactionDate: {
        date?: string
        timeStatus: TransactionTimeStatus
        time?: string
        expect?: LocalDate
        throws?: boolean
    }[]
    balanceAsOf: {
        input: string
        expect?: LocalDate
        cutoff?: boolean
        throws?: boolean
    }[]
}

const fixtures: Fixtures = JSON.parse(
    readFileSync(
        resolve(import.meta.dirname, '../src/tools/parsing-fixtures.json'),
        'utf8',
    ),
)

function toDate(local: LocalDate): Date {
    return new Date(
        local.year,
        local.month - 1,
        local.day,
        local.hour ?? 0,
        local.minute ?? 0,
        local.second ?? 0,
        local.millisecond ?? 0,
    )
}

const now = toDate(fixtures.now)

describe('parseAmountToCents fixtures', () => {
    for (const c of fixtures.amountToCents) {
        it(`${c.input} → ${c.cents}`, () => {
            expect(parseAmountToCents(c.input)).toBe(BigInt(c.cents))
        })
    }
})

describe('parseNaturalDate fixtures', () => {
    for (const c of fixtures.naturalDate) {
        it(c.input, () => {
            if (c.throws) {
                expect(() => parseNaturalDate(c.input, now)).toThrow()
                return
            }
            if (!c.expect) throw new Error('fixture needs expect or throws')
            expect(parseNaturalDate(c.input, now)).toBe(
                BigInt(toDate(c.expect).getTime()),
            )
        })
    }
})

describe('parseTransactionDate fixtures', () => {
    for (const c of fixtures.transactionDate) {
        it(`date=${c.date ?? '∅'} status=${c.timeStatus} time=${c.time ?? '∅'}`, () => {
            if (c.throws) {
                expect(() =>
                    parseTransactionDate(c.date, c.timeStatus, c.time, now),
                ).toThrow()
                return
            }
            if (!c.expect) throw new Error('fixture needs expect or throws')
            expect(
                parseTransactionDate(c.date, c.timeStatus, c.time, now),
            ).toBe(BigInt(toDate(c.expect).getTime()))
        })
    }
})

describe('balanceAsOfMs fixtures', () => {
    for (const c of fixtures.balanceAsOf) {
        it(c.input, () => {
            if (c.throws) {
                expect(() => balanceAsOfMs(c.input, now)).toThrow()
                return
            }
            if (c.cutoff) {
                expect(balanceAsOfMs(c.input, now)).toBe(
                    BigInt(pastCutoffMs(now)),
                )
                return
            }
            if (!c.expect) {
                throw new Error('fixture needs expect, cutoff or throws')
            }
            expect(balanceAsOfMs(c.input, now)).toBe(
                BigInt(toDate(c.expect).getTime()),
            )
        })
    }
})
