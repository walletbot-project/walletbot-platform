// Calendar math for the `calculateDate` tool.
//
// The native (Dart) side mirrors this in apps/native/lib/voice/tool_calc.dart;
// parity is locked by calc-fixtures.json (see calc.ts for the runner paths).
//
// Semantics (identical on both platforms):
// - Everything operates on calendar days: the clock is dropped after parsing.
// - Month/year addition clamps to the target month's last day
//   (Jan 31 + 1 month = Feb 28).
// - diff counts whole units actually elapsed from `date` to `otherDate`,
//   signed (positive when otherDate is after date), clamp-aware for
//   months/years: n whole months elapsed iff addMonths(date, n) is not past
//   otherDate.
// - Weeks run Monday–Sunday (ISO), regardless of the user's locale.
// - Weekday names are English lowercase; the model translates when speaking.

import {
    addDays,
    addMonths,
    addWeeks,
    addYears,
    differenceInCalendarDays,
    endOfMonth,
    endOfWeek,
    endOfYear,
    startOfMonth,
    startOfWeek,
    startOfYear,
} from 'date-fns'
import { parseNaturalDate } from './parsing'

export const DATE_CALC_OPERATIONS = [
    'add',
    'subtract',
    'diff',
    'startOf',
    'endOf',
    'dayOfWeek',
] as const
export const DATE_CALC_UNITS = ['day', 'week', 'month', 'year'] as const

export type DateCalcOperation = (typeof DATE_CALC_OPERATIONS)[number]
export type DateCalcUnit = (typeof DATE_CALC_UNITS)[number]

export type DateCalcArgs = {
    operation: DateCalcOperation
    date: string
    amount?: number
    unit?: DateCalcUnit
    otherDate?: string
}

export type DateCalcResult =
    | { date: string; dayOfWeek: string }
    | { from: string; to: string; unit: DateCalcUnit; value: number }

// Date.getDay() order: 0 = Sunday.
const WEEKDAYS = [
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
] as const

function parseCalendarDay(input: string, now: Date): Date {
    const ms = parseNaturalDate(input, now)
    const parsed = new Date(Number(ms))
    return new Date(parsed.getFullYear(), parsed.getMonth(), parsed.getDate())
}

function isoDate(date: Date): string {
    const pad = (n: number) => String(n).padStart(2, '0')
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

function dayResult(date: Date): DateCalcResult {
    return { date: isoDate(date), dayOfWeek: WEEKDAYS[date.getDay()] }
}

function addUnits(date: Date, amount: number, unit: DateCalcUnit): Date {
    switch (unit) {
        case 'day':
            return addDays(date, amount)
        case 'week':
            return addWeeks(date, amount)
        case 'month':
            return addMonths(date, amount)
        case 'year':
            return addYears(date, amount)
    }
}

function wholeUnitsBetween(from: Date, to: Date, unit: DateCalcUnit): number {
    if (unit === 'day' || unit === 'week') {
        const days = differenceInCalendarDays(to, from)
        return unit === 'day' ? days : Math.trunc(days / 7)
    }
    const months =
        (to.getFullYear() - from.getFullYear()) * 12 +
        (to.getMonth() - from.getMonth())
    let n = unit === 'month' ? months : Math.trunc(months / 12)
    // The raw month/year count may overshoot by one because of day-of-month
    // clamping; correct toward zero until add(from, n) is not past `to`.
    if (n > 0 && addUnits(from, n, unit) > to) n -= 1
    else if (n < 0 && addUnits(from, n, unit) < to) n += 1
    return n
}

/**
 * Executes one calculateDate operation. Throws with a model-readable message
 * on missing/invalid arguments or an unparseable date.
 */
export function runCalculateDate(
    args: DateCalcArgs,
    now: Date = new Date(),
): DateCalcResult {
    const base = parseCalendarDay(args.date, now)
    switch (args.operation) {
        case 'add':
        case 'subtract': {
            const { amount, unit } = args
            if (amount === undefined || !Number.isInteger(amount)) {
                throw new Error(
                    'amount (a whole number of units) is required for add/subtract',
                )
            }
            if (unit === undefined) {
                throw new Error('unit is required for add/subtract')
            }
            const signed = args.operation === 'add' ? amount : -amount
            return dayResult(addUnits(base, signed, unit))
        }
        case 'diff': {
            const { unit, otherDate } = args
            if (otherDate === undefined) {
                throw new Error('otherDate is required for diff')
            }
            if (unit === undefined) {
                throw new Error('unit is required for diff')
            }
            const other = parseCalendarDay(otherDate, now)
            return {
                from: isoDate(base),
                to: isoDate(other),
                unit,
                value: wholeUnitsBetween(base, other, unit),
            }
        }
        case 'startOf':
        case 'endOf': {
            const { unit } = args
            if (unit === undefined || unit === 'day') {
                throw new Error(
                    'unit (week, month or year) is required for startOf/endOf',
                )
            }
            const start = args.operation === 'startOf'
            switch (unit) {
                case 'week':
                    return dayResult(
                        start
                            ? startOfWeek(base, { weekStartsOn: 1 })
                            : endOfWeek(base, { weekStartsOn: 1 }),
                    )
                case 'month':
                    return dayResult(
                        start ? startOfMonth(base) : endOfMonth(base),
                    )
                case 'year':
                    return dayResult(
                        start ? startOfYear(base) : endOfYear(base),
                    )
            }
            break
        }
        case 'dayOfWeek':
            return dayResult(base)
    }
    throw new Error(`Unknown operation: ${String(args.operation)}`)
}
