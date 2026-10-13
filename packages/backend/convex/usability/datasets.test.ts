import { describe, expect, it } from 'vitest'
import {
    artMs,
    type CivilDay,
    formatCivilDay,
    type PlanTransaction,
    parseCivilDay,
    scenario0Plan,
    scenario2Plan,
} from './datasets'

function everyDay(from: string, to: string): CivilDay[] {
    const days: CivilDay[] = []
    const start = parseCivilDay(from)
    const end = parseCivilDay(to)
    if (!start || !end) throw new Error('bad range')
    let cursor = Date.UTC(start.year, start.month - 1, start.day)
    const last = Date.UTC(end.year, end.month - 1, end.day)
    while (cursor <= last) {
        const date = new Date(cursor)
        days.push({
            year: date.getUTCFullYear(),
            month: date.getUTCMonth() + 1,
            day: date.getUTCDate(),
        })
        cursor += 86_400_000
    }
    return days
}

const DAYS = everyDay('2026-01-01', '2027-12-31')

const TABLE_MOVEMENT_COUNT = 23

function runningMinimum(
    transactions: PlanTransaction[],
    accountKey: string,
    untilMs: number,
): number {
    let balance = 0
    let minimum = Number.POSITIVE_INFINITY
    for (const txn of transactions) {
        if (txn.dateMs >= untilMs) break
        if (txn.type === 'balance_adjustment') {
            if (txn.accountKey === accountKey) balance = txn.amountCents
        } else if (txn.type === 'transfer') {
            if (txn.accountKey === accountKey) balance -= txn.amountCents
            if (txn.toAccountKey === accountKey) {
                balance += txn.toAmountCents ?? txn.amountCents
            }
        } else if (txn.accountKey === accountKey) {
            balance +=
                txn.type === 'income' ? txn.amountCents : -txn.amountCents
        }
        if (txn.accountKey === accountKey || txn.toAccountKey === accountKey) {
            minimum = Math.min(minimum, balance)
        }
    }
    return minimum
}

describe('parseCivilDay', () => {
    it('accepts real dates and rejects impossible ones', () => {
        expect(parseCivilDay('2026-10-05')).toEqual({
            year: 2026,
            month: 10,
            day: 5,
        })
        expect(parseCivilDay('2026-02-30')).toBeNull()
        expect(parseCivilDay('2026-10-5')).toBeNull()
    })
})

describe('scenario0Plan', () => {
    it('opens three peso accounts ten days before the session', () => {
        const day = { year: 2026, month: 10, day: 5 }
        const plan = scenario0Plan(day)
        expect(plan.accounts.map((account) => account.name)).toEqual([
            'Efectivo',
            'MercadoPago',
            'Tarjeta de crédito',
        ])
        expect(plan.categories).toHaveLength(8)
        expect(plan.transactions.map((txn) => txn.amountCents)).toEqual([
            4_500_000, 38_000_000, -25_000_000,
        ])
        for (const txn of plan.transactions) {
            expect(txn.type).toBe('balance_adjustment')
            expect(txn.dateMs).toBeLessThan(
                artMs({ year: 2026, month: 9, day: 26 }, 0, 0),
            )
        }
    })
})

describe('scenario2Plan', () => {
    it.each(
        DAYS.map((day) => [formatCivilDay(day), day] as const),
    )('keeps the answer sheet true for a session on %s', (_label, day) => {
        const { plan, answers } = scenario2Plan(day)
        const sessionStart = artMs(day, 6, 0)

        expect(answers.mercadoPagoBalanceCents).toBe(8_732_000)
        expect(answers.hardware.amountCents).toBe(2_345_000)
        expect(answers.hardware.accountName).toBe('Efectivo')
        expect(answers.supermarket).toEqual({
            totalCents: 41_230_000,
            count: 6,
        })
        expect(answers.martina).toEqual({
            totalCents: 18_650_000,
            count: 5,
            withGiftCents: 22_650_000,
            withOldOutingCents: 22_150_000,
        })
        expect(answers.fridge.paidCount).toBe(3)
        const dueGap =
            (Date.parse(`${answers.fridge.fourthDueDay}T12:00:00Z`) -
                Date.UTC(day.year, day.month - 1, day.day, 12)) /
            86_400_000
        expect(dueGap).toBeGreaterThanOrEqual(3)
        expect(dueGap).toBeLessThanOrEqual(7)
        expect(answers.savings.currentUsdCents).toBe(260_000)
        expect(answers.savings.months).toBe(12)

        const { months } = answers
        expect(months.lastTotalCents).toBeGreaterThan(months.previousTotalCents)
        const deltas = [...months.categories].sort(
            (a, b) =>
                Math.abs(b.lastCents - b.previousCents) -
                Math.abs(a.lastCents - a.previousCents),
        )
        expect(deltas[0].name).toBe('Salud')
        expect(deltas[0].lastCents - deltas[0].previousCents).toBe(18_000_000)

        const hardwareStores = plan.transactions.filter((txn) =>
            txn.name.toLowerCase().includes('ferreter'),
        )
        expect(hardwareStores).toHaveLength(1)
        expect(
            plan.transactions.filter((txn) => txn.tagKeys?.includes('martina')),
        ).toHaveLength(7)
        const health = plan.transactions.filter(
            (txn) => txn.categoryKey === 'salud',
        )
        expect(health.map((txn) => txn.name).sort()).toEqual([
            'Dentista',
            'Farmacia',
            'Farmacia',
            'Farmacia',
            'Farmacia',
            'Farmacia',
        ])

        const oneOffExpenses = plan.transactions.filter(
            (txn) => txn.type === 'expense' && txn.recurrence === undefined,
        )
        const filler = oneOffExpenses.length - TABLE_MOVEMENT_COUNT
        expect(filler).toBeGreaterThanOrEqual(150)
        expect(filler).toBeLessThanOrEqual(250)

        for (const txn of plan.transactions) {
            if (
                txn.recurrence === undefined &&
                txn.type !== 'balance_adjustment'
            ) {
                expect(txn.dateMs).toBeLessThan(sessionStart)
            }
            if (txn.type !== 'balance_adjustment') {
                expect(txn.amountCents).toBeGreaterThan(0)
            }
        }

        expect(
            runningMinimum(plan.transactions, 'mercadopago', sessionStart),
        ).toBeGreaterThanOrEqual(0)
        expect(
            runningMinimum(plan.transactions, 'galicia', sessionStart),
        ).toBeGreaterThanOrEqual(0)
        expect(
            runningMinimum(plan.transactions, 'ahorro', sessionStart),
        ).toBeGreaterThanOrEqual(0)
    })

    it('keeps full months near the designed totals', () => {
        const totals: number[] = []
        const last: number[] = []
        const previous: number[] = []
        for (const day of DAYS) {
            const { answers } = scenario2Plan(day)
            last.push(answers.months.lastTotalCents / 100)
            previous.push(answers.months.previousTotalCents / 100)
            totals.push(
                (answers.months.lastTotalCents -
                    answers.months.previousTotalCents) /
                    100,
            )
        }
        expect(Math.min(...last)).toBeGreaterThanOrEqual(1_700_000)
        expect(Math.max(...last)).toBeLessThanOrEqual(1_830_000)
        expect(Math.min(...previous)).toBeGreaterThanOrEqual(1_520_000)
        expect(Math.max(...previous)).toBeLessThanOrEqual(1_700_000)
        expect(Math.min(...totals)).toBeGreaterThanOrEqual(100_000)
        expect(Math.max(...totals)).toBeLessThanOrEqual(270_000)
    })
})
