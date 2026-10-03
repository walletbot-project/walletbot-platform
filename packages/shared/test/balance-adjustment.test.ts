// The TS half of the balance-adjustment parity suite. The same fixture table
// is the contract the backend and native implementations must match — a
// behavioural change on one side has to update the fixtures for all of them.

import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import {
    adjustmentPreviousBalance,
    compareLedgerOrder,
    isBeforeInLedger,
    type LedgerEntry,
    ledgerDelta,
    reconcileAdjustments,
} from '../src/balance-adjustment'
import { TXN_TYPES, type TxnType } from '../src/dashboard/filter'

type RawEntry = {
    id: string
    type: string
    accountId: string
    toAccountId?: string
    amount: number
    toAmount?: number
    balanceAfter?: number
    date: number
    createdAt: number
    isArchived?: boolean
}

type Fixtures = {
    cases: {
        name: string
        entries: RawEntry[]
        expected: Record<string, number>
    }[]
}

function isTxnType(value: string): value is TxnType {
    return TXN_TYPES.some((t) => t === value)
}

function toEntry(raw: RawEntry): LedgerEntry {
    if (!isTxnType(raw.type)) throw new Error(`unknown type ${raw.type}`)
    return {
        id: raw.id,
        type: raw.type,
        accountId: raw.accountId,
        toAccountId: raw.toAccountId,
        amount: BigInt(raw.amount),
        toAmount: raw.toAmount === undefined ? undefined : BigInt(raw.toAmount),
        balanceAfter:
            raw.balanceAfter === undefined
                ? undefined
                : BigInt(raw.balanceAfter),
        date: BigInt(raw.date),
        createdAt: BigInt(raw.createdAt),
        isArchived: raw.isArchived ?? false,
    }
}

const fixtures: Fixtures = JSON.parse(
    readFileSync(
        resolve(import.meta.dirname, '../src/balance-adjustment-fixtures.json'),
        'utf8',
    ),
)

function entry(overrides: Partial<LedgerEntry> & { id: string }): LedgerEntry {
    return {
        type: 'expense',
        accountId: 'cash',
        amount: 0n,
        date: 0n,
        createdAt: 0n,
        isArchived: false,
        ...overrides,
    }
}

describe('balance adjustment fixtures', () => {
    for (const fixture of fixtures.cases) {
        it(fixture.name, () => {
            const amounts = reconcileAdjustments(fixture.entries.map(toEntry))
            const expected = new Map(
                Object.entries(fixture.expected).map(([id, cents]) => [
                    id,
                    BigInt(cents),
                ]),
            )
            expect(amounts).toEqual(expected)
        })
    }
})

describe('ledgerDelta', () => {
    it('subtracts outflows and adds inflows on the source account', () => {
        expect(ledgerDelta(entry({ id: 'e', amount: 100n }), 'cash')).toBe(
            -100n,
        )
        expect(
            ledgerDelta(
                entry({ id: 'i', type: 'income', amount: 100n }),
                'cash',
            ),
        ).toBe(100n)
        expect(
            ledgerDelta(
                entry({ id: 'a', type: 'balance_adjustment', amount: -40n }),
                'cash',
            ),
        ).toBe(-40n)
    })

    it('credits a transfer destination with toAmount', () => {
        const t = entry({
            id: 't',
            type: 'transfer',
            accountId: 'ars',
            toAccountId: 'usd',
            amount: 1500n,
            toAmount: 1n,
        })
        expect(ledgerDelta(t, 'ars')).toBe(-1500n)
        expect(ledgerDelta(t, 'usd')).toBe(1n)
    })

    it('ignores archived entries and other accounts', () => {
        expect(
            ledgerDelta(
                entry({ id: 'e', amount: 100n, isArchived: true }),
                'cash',
            ),
        ).toBe(0n)
        expect(ledgerDelta(entry({ id: 'e', amount: 100n }), 'bank')).toBe(0n)
    })
})

describe('compareLedgerOrder', () => {
    it('puts a same-date movement before the adjustment', () => {
        const adj = entry({
            id: 'adj',
            type: 'balance_adjustment',
            date: 10n,
            createdAt: 1n,
        })
        const later = entry({ id: 'later', date: 10n, createdAt: 2n })
        expect(isBeforeInLedger(later, adj)).toBe(true)
        expect(isBeforeInLedger(adj, later)).toBe(false)
    })

    it('puts a movement dated after the adjustment after it', () => {
        const adj = entry({ id: 'adj', type: 'balance_adjustment', date: 10n })
        expect(isBeforeInLedger(entry({ id: 'm', date: 11n }), adj)).toBe(false)
    })

    it('is total: creation, then id', () => {
        const a = entry({ id: 'a', date: 1n, createdAt: 2n })
        const b = entry({ id: 'b', date: 1n, createdAt: 1n })
        const c = entry({ id: 'c', date: 1n, createdAt: 1n })
        expect([a, c, b].sort(compareLedgerOrder).map((e) => e.id)).toEqual([
            'b',
            'c',
            'a',
        ])
        expect(compareLedgerOrder(a, a)).toBe(0)
    })
})

describe('adjustmentPreviousBalance', () => {
    it('is the declared balance minus the derived amount', () => {
        expect(
            adjustmentPreviousBalance({
                amount: 200000n,
                balanceAfter: 500000n,
            }),
        ).toBe(300000n)
    })
})
