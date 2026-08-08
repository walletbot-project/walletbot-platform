// Shared types, formatters and grouping logic for the Activity view.
// Mirrors the native app's activity screen (apps/native/lib/screens/activity.dart)
// so both clients read and present transactions the same way.
//
// The label-producing helpers take the active catalog and BCP 47 tag rather
// than reading a module-level locale, so they stay pure and testable.

import type { Messages } from '@/lib/i18n'

export type TransactionType =
    | 'expense'
    | 'income'
    | 'transfer'
    | 'balance_adjustment'

export type TransactionTimeStatus = 'confirmed' | 'approximation' | 'none'

export type TransactionTransferSide = 'source' | 'destination'

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
    currency: string
    toCurrency?: string
    toAccountId?: string
    dateConfirmed: boolean
    timeStatus?: TransactionTimeStatus
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

/** Capitalised weekday name in the active locale, e.g. `Lunes` / `Monday`. */
function weekdayName(date: Date, locale: string): string {
    const name = new Intl.DateTimeFormat(locale, { weekday: 'long' }).format(
        date,
    )
    return name.charAt(0).toUpperCase() + name.slice(1)
}

function groupThousands(value: number, locale: string): string {
    return new Intl.NumberFormat(locale, {
        maximumFractionDigits: 0,
    }).format(Math.trunc(Math.abs(value)))
}

/** Unsigned amount, e.g. `$1.234`. Cents are rounded to whole units. */
export function formatAmount(
    cents: number,
    locale: string,
    currencySymbol = '$',
): string {
    const whole = Math.round(Math.abs(cents) / 100)
    return `${currencySymbol}${groupThousands(whole, locale)}`
}

/** Signed amount, e.g. `+ $ 1.234` / `- $ 1.234`. */
export function formatSignedAmount(
    cents: number,
    locale: string,
    currencySymbol = '$',
): string {
    const sign = cents < 0 ? '-' : cents > 0 ? '+' : ''
    const whole = Math.round(Math.abs(cents) / 100)
    return `${sign ? `${sign} ` : ''}${currencySymbol} ${groupThousands(whole, locale)}`
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

/** Numeric date in the active locale, e.g. `10/7/2026` (es) / `7/10/2026` (en). */
export function formatNumericDate(date: Date, locale: string): string {
    return new Intl.DateTimeFormat(locale).format(date)
}

/** Day-group header label: "today", "yesterday", a weekday name, or a date. */
export function sectionLabel(
    dayMs: number,
    nowMs: number,
    messages: Messages,
    locale: string,
): string {
    const day = startOfDay(new Date(dayMs))
    const today = startOfDay(new Date(nowMs))
    const diffDays = Math.round((today.getTime() - day.getTime()) / 86_400_000)
    if (diffDays === 0) return messages.activity.today
    if (diffDays === 1) return messages.activity.yesterday
    if (diffDays > 1 && diffDays < 7) return weekdayName(day, locale)
    return formatNumericDate(day, locale)
}

/** Description plus the inferred-day notice, when applicable. */
export function estimatedDescription(
    t: ActivityTransaction,
    messages: Messages,
    locale: string,
): string | null {
    const parts = [
        ...(t.dateConfirmed
            ? []
            : [
                  messages.activity.estimatedDay({
                      weekday: weekdayName(new Date(Number(t.date)), locale),
                  }),
              ]),
        ...(t.description ? [t.description] : []),
    ]
    return parts.length > 0 ? parts.join(' · ') : null
}

export function transactionTimeStatus(
    t: ActivityTransaction,
): TransactionTimeStatus {
    return t.timeStatus ?? 'none'
}

export function formatTransactionTime(
    epoch: bigint | number,
    locale: string,
): string {
    return new Intl.DateTimeFormat(locale, {
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
    }).format(new Date(Number(epoch)))
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
    | {
          kind: 'txn'
          key: string
          txn: ActivityTransaction
          title: string
          amountCents: number
          currency: string
          accountId: string
          transferSide?: TransactionTransferSide
      }

/** Sorts by the real timestamp and groups transactions into day sections. */
export function buildListEntries(
    items: readonly ActivityTransaction[],
    nowMs: number,
    messages: Messages,
    locale: string,
): ListEntry[] {
    const entries: ListEntry[] = []
    let currentDay: number | null = null
    const sorted = [...items].sort((left, right) => {
        const byDate = Number(right.date - left.date)
        if (byDate !== 0) return byDate
        const byCreation = Number(right.createdAt - left.createdAt)
        if (byCreation !== 0) return byCreation
        return right.id.localeCompare(left.id)
    })

    for (const t of sorted) {
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
                label: sectionLabel(day, nowMs, messages, locale),
            })
            currentDay = day
        }
        if (t.type === 'transfer') {
            entries.push(
                {
                    kind: 'txn',
                    key: `${t.id}-source`,
                    txn: t,
                    title: messages.activity.transferSent,
                    amountCents: -Math.abs(Number(t.amount)),
                    currency: t.currency,
                    accountId: t.accountId,
                    transferSide: 'source',
                },
                {
                    kind: 'txn',
                    key: `${t.id}-destination`,
                    txn: t,
                    title: messages.activity.transferReceived,
                    amountCents: Math.abs(Number(t.toAmount ?? t.amount)),
                    currency: t.toCurrency ?? t.currency,
                    accountId: t.toAccountId ?? t.accountId,
                    transferSide: 'destination',
                },
            )
        } else {
            entries.push({
                kind: 'txn',
                key: t.id,
                txn: t,
                title: t.name,
                amountCents: signedAmountCents(t),
                currency: t.currency,
                accountId: t.accountId,
            })
        }
    }
    return entries
}
