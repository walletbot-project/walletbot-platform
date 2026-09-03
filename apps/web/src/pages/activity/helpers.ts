// Shared types, formatters and grouping logic for the Activity view.
// Mirrors the native app's activity screen (apps/native/lib/screens/activity.dart)
// so both clients read and present transactions the same way.
//
// The label-producing helpers take the active catalog and BCP 47 tag rather
// than reading a module-level locale, so they stay pure and testable.

import type { RecurrenceFrequency } from '@wallet-bot/shared'
import {
    EMPTY_FILTER,
    parseFilterConfig,
    type SimpleFilter,
    TXN_TYPES,
} from '@wallet-bot/shared'
import { type Messages, transactionName } from '@/lib/i18n'

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
    /** Set when the movement is one occurrence of a recurring rule. */
    recurrenceId?: string
    /** Its position in that rule's series, counting the anchor as 0. */
    recurrenceIndex?: bigint
}

/**
 * What another screen may hand the activity list through router state — an
 * account's "see all", a tag on a transaction. Only the dimensions a deep link
 * legitimately sets; the rest of the filter starts empty.
 */
export type ActivityFilterSeed = Partial<
    Pick<
        SimpleFilter,
        | 'types'
        | 'accountIds'
        | 'categoryIds'
        | 'tagIds'
        | 'dateFrom'
        | 'dateTo'
        | 'search'
    >
>

function stringList(value: unknown): string[] | null {
    if (!Array.isArray(value)) return null
    const items = value.filter(
        (item): item is string => typeof item === 'string',
    )
    return items.length === value.length ? items : null
}

/**
 * Reads a seed off `location.state`, which is whatever the previous screen put
 * there — untyped by React Router, so every field is checked rather than
 * asserted. Returns null when nothing usable was passed.
 */
export function readFilterSeed(state: unknown): SimpleFilter | null {
    if (typeof state !== 'object' || state === null) return null
    const seed: Record<string, unknown> = { ...state }

    // A dashboard tile hands over its whole saved filter rather than a few
    // dimensions, so the activity list shows exactly what the tile counted
    // (native `_activityFilterFor`). The canonical JSON is parsed, not trusted.
    if (typeof seed.filterConfig === 'string' && seed.filterConfig) {
        return parseFilterConfig(seed.filterConfig)
    }

    const types = stringList(seed.types)?.filter(
        (value): value is SimpleFilter['types'][number] =>
            (TXN_TYPES as readonly string[]).includes(value),
    )
    const accountIds = stringList(seed.accountIds)
    const categoryIds = stringList(seed.categoryIds)
    const tagIds = stringList(seed.tagIds)
    const dateFrom = typeof seed.dateFrom === 'string' ? seed.dateFrom : null
    const dateTo = typeof seed.dateTo === 'string' ? seed.dateTo : null
    const search = typeof seed.search === 'string' ? seed.search : null

    const carries =
        (types && types.length > 0) ||
        (accountIds && accountIds.length > 0) ||
        (categoryIds && categoryIds.length > 0) ||
        (tagIds && tagIds.length > 0) ||
        dateFrom !== null ||
        dateTo !== null ||
        (search !== null && search !== '')
    if (!carries) return null

    return {
        ...EMPTY_FILTER,
        ...(types ? { types } : {}),
        ...(accountIds ? { accountIds } : {}),
        ...(categoryIds ? { categoryIds } : {}),
        ...(tagIds ? { tagIds } : {}),
        dateFrom,
        dateTo,
        search,
    }
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

function startOfDay(date: Date): Date {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate())
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

/**
 * How many filter groups the bar reports on its badge and renders as removable
 * chips. Deliberately the same four native counts
 * (`transaction_filters_bar.dart`), so the same filter shows the same badge on
 * both clients — the type chips and the search field are their own controls,
 * and the sheet's remaining dimensions are not summarised on either platform.
 */
export function activeFilterCount(filter: SimpleFilter): number {
    let count = 0
    if (filter.accountIds.length) count++
    if (filter.categoryIds.length) count++
    if (filter.tagIds.length) count++
    if (filter.dateFrom || filter.dateTo || filter.datePreset) count++
    return count
}

export function hasActiveFilters(filter: SimpleFilter): boolean {
    return activeFilterCount(filter) > 0
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
                title: transactionName(t.name, t.type, messages),
                amountCents: signedAmountCents(t),
                currency: t.currency,
                accountId: t.accountId,
            })
        }
    }
    return entries
}

/**
 * How a cadence reads in a sentence. Deliberately the same catalogue the form
 * offers ("Mensual", "Cada 3 días"), so a rule is described identically where
 * it is created and where it is read back — the labels live in `addManual`
 * because that is where the vocabulary is defined.
 *
 * `customDays` is the one that differs: the form shows the chip "Cada X días"
 * with the interval in its own field, while here the interval is part of the
 * description.
 */
export function frequencyLabel(
    frequency: RecurrenceFrequency,
    dayInterval: number,
    messages: Messages,
): string {
    switch (frequency) {
        case 'daily':
            return messages.addManual.recurrenceDaily
        case 'weekly':
            return messages.addManual.recurrenceWeekly
        case 'monthly':
            return messages.addManual.recurrenceMonthly
        case 'yearly':
            return messages.addManual.recurrenceYearly
        case 'customDays':
            return messages.addManual.recurrenceEveryNDays(dayInterval)
    }
}

/** The rule and series reach as `v1/recurrences/queries:get` returns them. */
export type RecurrenceSeries = {
    frequency: RecurrenceFrequency
    dayInterval?: bigint
    endDate?: bigint
    count: number
    coveredThroughMs: bigint | null
}

/**
 * What the series reaches, shown beside the cadence.
 *
 * A bounded rule says where this movement sits in it ("3/12"): the total is
 * knowable, so the position is the useful fact. An open-ended one has no total
 * to be a fraction of, so it says how far the movements that exist go instead
 * — which is also exactly what the top-up button extends.
 */
export function seriesReachLabel(
    series: RecurrenceSeries,
    occurrenceIndex: bigint | undefined,
    messages: Messages,
    formatDate: (date: Date) => string,
): string | null {
    if (series.endDate !== undefined) {
        if (occurrenceIndex === undefined || series.count === 0) return null
        return messages.futureMovements.seriesPosition({
            index: Number(occurrenceIndex) + 1,
            total: series.count,
        })
    }
    if (series.coveredThroughMs === null) return null
    return messages.futureMovements.coveredThrough(
        formatDate(new Date(Number(series.coveredThroughMs))),
    )
}
