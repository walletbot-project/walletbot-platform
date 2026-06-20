// Shared types, formatters and grouping logic for the Activity view.
// Mirrors the native app's activity screen (apps/native/lib/screens/activity.dart)
// so both clients read and present transactions the same way.

export type TransactionType =
    | 'expense'
    | 'income'
    | 'transfer'
    | 'balance_adjustment'

/**
 * The shape of a transaction this view actually reads. Convex returns the full
 * document (with extra fields and `int64` columns as `bigint`); this is a
 * structural subset so the helpers stay decoupled from the generated type.
 */
export type ActivityTransaction = {
    id: string
    type: TransactionType
    name: string
    description?: string | null
    date: bigint
    createdAt: bigint
    accountId: string
    categoryId: string
    amount: bigint
    toAmount?: bigint
    dateConfirmed: boolean
    isArchived: boolean
    tagIds?: string[]
}

export type TransactionFilters = {
    search: string
    accountIds: string[]
    categoryIds: string[]
    tagIds: string[]
    dateFrom?: Date
    dateTo?: Date
}

export const EMPTY_FILTERS: TransactionFilters = {
    search: '',
    accountIds: [],
    categoryIds: [],
    tagIds: [],
}

const SPANISH_WEEKDAYS = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
]

/** Maps JS `getDay()` (0 = Sunday) onto the Monday-first weekday array. */
function weekdayName(date: Date): string {
    return SPANISH_WEEKDAYS[(date.getDay() + 6) % 7]
}

function groupThousands(value: number): string {
    const digits = Math.trunc(Math.abs(value)).toString()
    let out = ''
    for (let i = 0; i < digits.length; i++) {
        if (i > 0 && (digits.length - i) % 3 === 0) out += '.'
        out += digits[i]
    }
    return out
}

/** Unsigned amount, e.g. `$1.234`. Cents are rounded to whole units. */
export function formatAmount(cents: number, currencySymbol = '$'): string {
    const whole = Math.round(Math.abs(cents) / 100)
    return `${currencySymbol}${groupThousands(whole)}`
}

/** Signed amount, e.g. `+ $ 1.234` / `- $ 1.234`. */
export function formatSignedAmount(
    cents: number,
    currencySymbol = '$',
): string {
    const sign = cents < 0 ? '-' : '+'
    const whole = Math.round(Math.abs(cents) / 100)
    return `${sign} ${currencySymbol} ${groupThousands(whole)}`
}

function startOfDay(date: Date): Date {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

function endOfDay(date: Date): Date {
    return new Date(
        date.getFullYear(),
        date.getMonth(),
        date.getDate(),
        23,
        59,
        59,
        999,
    )
}

function formatDDMMYYYY(date: Date): string {
    const dd = date.getDate().toString().padStart(2, '0')
    const mm = (date.getMonth() + 1).toString().padStart(2, '0')
    return `${dd}/${mm}/${date.getFullYear()}`
}

/** Day-group header label: "Hoy", "Ayer", a weekday name, or a date. */
export function sectionLabel(dayMs: number, nowMs: number): string {
    const day = startOfDay(new Date(dayMs))
    const today = startOfDay(new Date(nowMs))
    const diffDays = Math.round((today.getTime() - day.getTime()) / 86_400_000)
    if (diffDays === 0) return 'Hoy'
    if (diffDays === 1) return 'Ayer'
    if (diffDays > 1 && diffDays < 7) return weekdayName(day)
    return formatDDMMYYYY(day)
}

/** Secondary line shown when a date was inferred rather than confirmed. */
export function estimatedDescription(t: ActivityTransaction): string | null {
    if (t.dateConfirmed) return null
    return `${weekdayName(new Date(Number(t.date)))} (estimado)`
}

/**
 * Signed cents for display: expenses negative, income/transfers positive,
 * balance adjustments keep their stored sign.
 */
export function signedAmountCents(t: ActivityTransaction): number {
    const amount = Number(t.amount)
    switch (t.type) {
        case 'expense':
            return -Math.abs(amount)
        case 'income':
        case 'transfer':
            return Math.abs(amount)
        case 'balance_adjustment':
            return amount
    }
}

export type MonthlyAggregates = {
    incomeCents: number
    expensesCents: number
    balanceCents: number
}

/** Income / expenses / net for a set of transactions (used by the summary card). */
export function aggregateMonth(
    items: readonly ActivityTransaction[],
): MonthlyAggregates {
    let income = 0
    let expenses = 0
    for (const t of items) {
        const amount = Number(t.amount)
        switch (t.type) {
            case 'income':
                income += amount
                break
            case 'expense':
                expenses += amount
                break
            case 'transfer':
                income += Number(t.toAmount ?? t.amount)
                expenses += amount
                break
            case 'balance_adjustment':
                if (amount >= 0) income += amount
                else expenses += -amount
                break
        }
    }
    return {
        incomeCents: income,
        expensesCents: expenses,
        balanceCents: income - expenses,
    }
}

/** Inclusive [start, end] of the month containing `now`, as ms-epoch bigints. */
export function monthRange(now: Date): { from: bigint; to: bigint } {
    const start = new Date(now.getFullYear(), now.getMonth(), 1)
    const end = new Date(now.getFullYear(), now.getMonth() + 1, 1)
    return { from: BigInt(start.getTime()), to: BigInt(end.getTime() - 1) }
}

export function dateFromMs(date: Date | undefined): bigint | undefined {
    return date ? BigInt(startOfDay(date).getTime()) : undefined
}

export function dateToMs(date: Date | undefined): bigint | undefined {
    return date ? BigInt(endOfDay(date).getTime()) : undefined
}

export function advancedFilterCount(f: TransactionFilters): number {
    let count = 0
    if (f.accountIds.length) count++
    if (f.categoryIds.length) count++
    if (f.tagIds.length) count++
    if (f.dateFrom || f.dateTo) count++
    return count
}

export function hasAdvancedFilters(f: TransactionFilters): boolean {
    return advancedFilterCount(f) > 0
}

/**
 * Client-side predicate applied on top of the server's index-narrowed page.
 * The backend narrows by a single account/category plus the date range; this
 * refines the rest (type chip, text search, multi-select, tags) so any filter
 * combination stays correct regardless of what the server could index.
 */
export function matchesFilters(
    t: ActivityTransaction,
    f: TransactionFilters,
    type: TransactionType | null,
): boolean {
    if (t.isArchived) return false
    if (type && t.type !== type) return false

    const search = f.search.trim().toLowerCase()
    if (search) {
        const nameMatches = t.name.toLowerCase().includes(search)
        const descriptionMatches = (t.description ?? '')
            .toLowerCase()
            .includes(search)
        if (!nameMatches && !descriptionMatches) return false
    }

    if (f.accountIds.length && !f.accountIds.includes(t.accountId)) return false
    if (f.categoryIds.length && !f.categoryIds.includes(t.categoryId))
        return false

    if (f.tagIds.length) {
        const ids = t.tagIds ?? []
        if (!f.tagIds.some((id) => ids.includes(id))) return false
    }

    if (f.dateFrom && Number(t.date) < startOfDay(f.dateFrom).getTime())
        return false
    if (f.dateTo && Number(t.date) > endOfDay(f.dateTo).getTime()) return false

    return true
}

export type ListEntry =
    | { kind: 'header'; key: string; label: string }
    | { kind: 'txn'; key: string; txn: ActivityTransaction }

/** Groups transactions (already sorted by date desc) into day sections. */
export function buildListEntries(
    items: readonly ActivityTransaction[],
    nowMs: number,
): ListEntry[] {
    const entries: ListEntry[] = []
    let currentDay: number | null = null
    for (const t of items) {
        const dt = new Date(Number(t.date))
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
        entries.push({ kind: 'txn', key: t.id, txn: t })
    }
    return entries
}
