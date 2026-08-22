/**
 * Labels, operator sets and value defaults for the canonical filter tree —
 * everything the filter editor needs that is pure. Ported from native's
 * `filter_sheet.dart` (`_fieldLabels`, `_operatorsFor`, `_operatorLabel`,
 * `_defaultCondition`) so a condition built on one client reads and behaves the
 * same on the other.
 */

import type {
    AccountDirection,
    DatePreset,
    FilterCondition,
    TagMatch,
    TxnStatus,
    TxnType,
} from '@wallet-bot/shared'
import type { Messages } from '@/lib/i18n'

/** The fields the editor can build a condition on, in the order native lists. */
export const FILTER_FIELDS = [
    'type',
    'status',
    'date',
    'account',
    'category',
    'tag',
    'currency',
    'amount',
    'text',
] as const

export type FilterField = (typeof FILTER_FIELDS)[number]

export function isFilterField(value: string): value is FilterField {
    return (FILTER_FIELDS as readonly string[]).includes(value)
}

export function txnTypeLabel(value: TxnType, t: Messages): string {
    switch (value) {
        case 'expense':
            return t.activity.typeExpense
        case 'income':
            return t.activity.typeIncome
        case 'transfer':
            return t.activity.typeTransfer
        case 'balance_adjustment':
            return t.activity.typeBalanceAdjustment
    }
}

export function txnStatusLabel(value: TxnStatus, t: Messages): string {
    switch (value) {
        case 'pending':
            return t.filters.statusPending
        case 'cleared':
            return t.filters.statusCleared
    }
}

export function datePresetLabel(value: DatePreset, t: Messages): string {
    switch (value) {
        case 'today':
            return t.filters.presetToday
        case 'this_week':
            return t.filters.presetThisWeek
        case 'this_month':
            return t.filters.presetThisMonth
        case 'last_month':
            return t.filters.presetLastMonth
        case 'this_year':
            return t.filters.presetThisYear
    }
}

export function accountDirectionLabel(
    value: AccountDirection,
    t: Messages,
): string {
    switch (value) {
        case 'source':
            return t.filters.directionSource
        case 'destination':
            return t.filters.directionDestination
        case 'either':
            return t.filters.directionEither
    }
}

export function tagMatchLabel(value: TagMatch, t: Messages): string {
    switch (value) {
        case 'any':
            return t.filters.matchAny
        case 'all':
            return t.filters.matchAll
    }
}

export function filterFieldLabel(field: FilterField, t: Messages): string {
    switch (field) {
        case 'type':
            return t.filters.type
        case 'status':
            return t.filters.status
        case 'date':
            return t.filters.date
        case 'account':
            return t.transaction.account
        case 'category':
            return t.transaction.category
        case 'tag':
            return t.activity.tags
        case 'currency':
            return t.filters.currency
        case 'amount':
            return t.filters.amount
        case 'text':
            return t.filters.text
    }
}

export function operatorLabel(operator: string, t: Messages): string {
    switch (operator) {
        case 'in':
            return t.filters.operatorIncludes
        case 'not in':
            return t.filters.operatorExcludes
        case 'relative':
            return t.filters.operatorRelative
        case 'between':
            return t.filters.operatorBetween
        case '>=':
            return t.filters.operatorGreaterEqual
        case '<=':
            return t.filters.operatorLessEqual
        case 'contains':
            return t.filters.operatorContains
        case 'not contains':
            return t.filters.operatorNotContains
        // Forward-compatible: an operator a newer client wrote is shown as it
        // is rather than blanked out.
        default:
            return operator
    }
}

/** The operators a field accepts — native's `_operatorsFor`, same order. */
export function operatorsFor(field: string): readonly string[] {
    switch (field) {
        case 'date':
            return ['relative', 'between']
        case 'amount':
            return ['between', '>=', '<=']
        case 'text':
            return ['contains', 'not contains']
        case 'type':
        case 'status':
        case 'account':
        case 'category':
        case 'tag':
        case 'currency':
            return ['in', 'not in']
        default:
            return ['in']
    }
}

/**
 * The condition a field starts on when it is picked — native's
 * `_defaultCondition`, value for value, so the same choice writes the same JSON
 * on both clients.
 */
export function defaultCondition(field: string): FilterCondition {
    switch (field) {
        case 'type':
            return { field: 'type', operator: 'in', value: ['expense'] }
        case 'status':
            return { field: 'status', operator: 'in', value: ['cleared'] }
        case 'date':
            return { field: 'date', operator: 'relative', value: 'this_month' }
        case 'account':
            return { field: 'account', operator: 'in', value: [] }
        case 'category':
            return { field: 'category', operator: 'in', value: [] }
        case 'tag':
            return { field: 'tag', operator: 'in', value: [] }
        case 'currency':
            return { field: 'currency', operator: 'in', value: [] }
        case 'amount':
            return {
                field: 'amount',
                operator: 'between',
                value: { min: null, max: null },
            }
        case 'text':
            return { field: 'text', operator: 'contains', value: '' }
        default:
            return { field: 'type', operator: 'in', value: [] }
    }
}

/**
 * Cents as the user types them — native's `_centsToText`: whole units when the
 * amount is round, two decimals otherwise.
 */
export function centsToText(cents: number | null): string {
    if (cents === null) return ''
    const value = cents / 100
    return Number.isInteger(value) ? String(value) : value.toFixed(2)
}

/** The inverse, tolerating a comma decimal separator as native does. */
export function textToCents(raw: string): number | null {
    const trimmed = raw.trim().replace(',', '.')
    if (!trimmed) return null
    const parsed = Number.parseFloat(trimmed)
    return Number.isFinite(parsed) ? Math.round(parsed * 100) : null
}

/** String list out of a condition value, ignoring anything else stored there. */
export function asStringList(value: unknown): string[] {
    return Array.isArray(value)
        ? value.filter((item): item is string => typeof item === 'string')
        : []
}

/** Plain-object view of a stored value, matching shared's own `asRecord`. */
function asRecord(value: unknown): Record<string, unknown> | null {
    return typeof value === 'object' && value !== null && !Array.isArray(value)
        ? (value as Record<string, unknown>)
        : null
}

/** `{min, max}` out of an amount condition value, in cents. */
export function asAmountRange(value: unknown): {
    min: number | null
    max: number | null
} {
    const record = asRecord(value)
    if (!record) return { min: null, max: null }
    return {
        min: typeof record.min === 'number' ? record.min : null,
        max: typeof record.max === 'number' ? record.max : null,
    }
}

/** `{from, to}` ISO dates out of a `between` date condition value. */
export function asDateRange(value: unknown): {
    from: string
    to: string
} | null {
    const record = asRecord(value)
    if (!record) return null
    if (typeof record.from !== 'string' || typeof record.to !== 'string') {
        return null
    }
    return { from: record.from, to: record.to }
}
