import {
    type ActivityTransaction,
    sectionLabel,
    signedAmountCents,
} from '../activity/helpers'
import type { TransactionRowIdentity } from '../activity/transaction-row'

// Recurrence cadence that generated an upcoming movement.
export type MockFrequency =
    | 'daily'
    | 'weekly'
    | 'monthly'
    | 'yearly'
    | 'customDays'

export const FREQUENCY_LABELS: Record<MockFrequency, string> = {
    daily: 'Diario',
    weekly: 'Semanal',
    monthly: 'Mensual',
    yearly: 'Anual',
    customDays: 'Cada X días',
}

/** The scope a recurring edit/delete applies to. */
export type RecurrenceScope = 'only-this' | 'all-future'

type MockAccount = { name: string; color: string; icon?: string }
type MockCategory = { name: string; color: string; icon?: string }

export const MOCK_ACCOUNTS: Record<string, MockAccount> = {
    'acc-bank': { name: 'Banco Nación', color: '#3B82F6' },
    'acc-cash': { name: 'Efectivo', color: '#22C55E' },
}

export const MOCK_CATEGORIES: Record<string, MockCategory> = {
    'cat-subscriptions': { name: 'Suscripciones', color: '#A855F7' },
    'cat-salary': { name: 'Sueldo', color: '#22C55E' },
    'cat-housing': { name: 'Vivienda', color: '#F97316' },
    'cat-health': { name: 'Salud', color: '#EF4444' },
    'cat-services': { name: 'Servicios', color: '#0EA5E9' },
}

// A future recurring movement: an ActivityTransaction (so it feeds the same
// row/format helpers Activity uses) plus its cadence and the id of the rule
// that generated it (shared across all occurrences of the same series).
export type FutureMovement = ActivityTransaction & {
    ruleId: string
    frequency: MockFrequency
    dayInterval?: number
}

/** How many upcoming occurrences we materialize per rule in the mock. */
const OCCURRENCES_PER_RULE = 3

type MockRule = {
    ruleId: string
    type: 'income' | 'expense'
    name: string
    description: string | null
    firstInDays: number
    hour: number
    accountId: string
    categoryId: string
    amount: bigint
    frequency: MockFrequency
    dayInterval?: number
}

const MOCK_RULES: MockRule[] = [
    {
        ruleId: 'spotify',
        type: 'expense',
        name: 'Spotify',
        description: 'Suscripción mensual',
        firstInDays: 2,
        hour: 9,
        accountId: 'acc-bank',
        categoryId: 'cat-subscriptions',
        amount: 550000n,
        frequency: 'monthly',
    },
    {
        ruleId: 'gym',
        type: 'expense',
        name: 'Gimnasio',
        description: 'Cuota mensual',
        firstInDays: 5,
        hour: 8,
        accountId: 'acc-bank',
        categoryId: 'cat-health',
        amount: 1500000n,
        frequency: 'monthly',
    },
    {
        ruleId: 'rent',
        type: 'expense',
        name: 'Alquiler',
        description: null,
        firstInDays: 10,
        hour: 9,
        accountId: 'acc-cash',
        categoryId: 'cat-housing',
        amount: 35000000n,
        frequency: 'monthly',
    },
    {
        ruleId: 'salary',
        type: 'income',
        name: 'Sueldo',
        description: 'Ingreso mensual',
        firstInDays: 12,
        hour: 9,
        accountId: 'acc-bank',
        categoryId: 'cat-salary',
        amount: 120000000n,
        frequency: 'monthly',
    },
    {
        ruleId: 'water',
        type: 'expense',
        name: 'Agua',
        description: 'Servicio bimestral',
        firstInDays: 21,
        hour: 11,
        accountId: 'acc-bank',
        categoryId: 'cat-services',
        amount: 1800000n,
        frequency: 'customDays',
        dayInterval: 60,
    },
]

/**
 * The date `steps` cadences after `anchorMs`. `steps === 0` returns the anchor
 * itself. Used both to materialize a rule's occurrences and to re-project the
 * future ones when an anchor occurrence moves.
 */
export function stepDate(
    anchorMs: bigint,
    frequency: MockFrequency,
    dayInterval: number | undefined,
    steps: number,
): bigint {
    const a = new Date(Number(anchorMs))
    const [y, m, d, hh, mi] = [
        a.getFullYear(),
        a.getMonth(),
        a.getDate(),
        a.getHours(),
        a.getMinutes(),
    ]
    switch (frequency) {
        case 'monthly':
            return BigInt(new Date(y, m + steps, d, hh, mi).getTime())
        case 'yearly':
            return BigInt(new Date(y + steps, m, d, hh, mi).getTime())
        default: {
            const stepDays =
                frequency === 'weekly'
                    ? 7
                    : frequency === 'daily'
                      ? 1
                      : (dayInterval ?? 30)
            return BigInt(
                new Date(y, m, d + stepDays * steps, hh, mi).getTime(),
            )
        }
    }
}

/** The date of the `index`-th occurrence of a rule, stepping by its cadence. */
function occurrenceDate(now: number, rule: MockRule, index: number): bigint {
    const base = new Date(now)
    const anchor = BigInt(
        new Date(
            base.getFullYear(),
            base.getMonth(),
            base.getDate() + rule.firstInDays,
            rule.hour,
        ).getTime(),
    )
    return stepDate(anchor, rule.frequency, rule.dayInterval, index)
}

export function buildMockMovements(now: number): FutureMovement[] {
    const shared = {
        createdAt: BigInt(now),
        currency: 'ARS',
        dateConfirmed: true,
        timeStatus: 'confirmed' as const,
        isArchived: false,
    }
    const movements: FutureMovement[] = []
    for (const rule of MOCK_RULES) {
        for (let i = 0; i < OCCURRENCES_PER_RULE; i++) {
            movements.push({
                ...shared,
                id: `${rule.ruleId}-${i}`,
                ruleId: rule.ruleId,
                type: rule.type,
                name: rule.name,
                description: rule.description,
                date: occurrenceDate(now, rule, i),
                accountId: rule.accountId,
                categoryId: rule.categoryId,
                amount: rule.amount,
                frequency: rule.frequency,
                dayInterval: rule.dayInterval,
            })
        }
    }
    return movements
}

export function identitiesFor(
    txn: ActivityTransaction,
): TransactionRowIdentity[] {
    const account = MOCK_ACCOUNTS[txn.accountId]
    const category = MOCK_CATEGORIES[txn.categoryId]
    return [
        ...(account
            ? [
                  {
                      type: 'account' as const,
                      label: `Cuenta: ${account.name}`,
                      icon: account.icon,
                      color: account.color,
                  },
              ]
            : []),
        ...(category
            ? [
                  {
                      type: 'category' as const,
                      label: `Categoría: ${category.name}`,
                      icon: category.icon,
                      color: category.color,
                  },
              ]
            : []),
    ]
}

export type FutureEntry =
    | { kind: 'header'; key: string; label: string }
    | { kind: 'txn'; key: string; txn: FutureMovement; amountCents: number }

/**
 * Groups movements into day sections, sorted **ascending** (soonest first) —
 * the opposite of the Activity history, which shows newest first. These are
 * upcoming movements, so the nearest one belongs at the top.
 */
export function buildFutureEntries(
    items: readonly FutureMovement[],
    nowMs: number,
): FutureEntry[] {
    const sorted = [...items].sort((left, right) => {
        const byDate = Number(left.date - right.date)
        if (byDate !== 0) return byDate
        return left.id.localeCompare(right.id)
    })

    const entries: FutureEntry[] = []
    let currentDay: number | null = null
    for (const txn of sorted) {
        const dt = new Date(Number(txn.date))
        const day = new Date(
            dt.getFullYear(),
            dt.getMonth(),
            dt.getDate(),
        ).getTime()
        if (currentDay === null || day !== currentDay) {
            entries.push({
                kind: 'header',
                key: `header-${day}`,
                label: sectionLabel(day, nowMs),
            })
            currentDay = day
        }
        entries.push({
            kind: 'txn',
            key: txn.id,
            txn,
            amountCents: signedAmountCents(txn),
        })
    }
    return entries
}

// ── Date <-> input helpers ──────────────────────────────────────────────

export function toDateInput(ms: bigint): string {
    const d = new Date(Number(ms))
    const yyyy = d.getFullYear().toString().padStart(4, '0')
    const mm = (d.getMonth() + 1).toString().padStart(2, '0')
    const dd = d.getDate().toString().padStart(2, '0')
    return `${yyyy}-${mm}-${dd}`
}

export function toTimeInput(ms: bigint): string {
    const d = new Date(Number(ms))
    const hh = d.getHours().toString().padStart(2, '0')
    const mi = d.getMinutes().toString().padStart(2, '0')
    return `${hh}:${mi}`
}

export function fromDateTimeInputs(dateStr: string, timeStr: string): bigint {
    const [y, m, d] = dateStr.split('-').map(Number)
    const [hh, mi] = (timeStr || '00:00').split(':').map(Number)
    return BigInt(new Date(y, m - 1, d, hh || 0, mi || 0).getTime())
}
