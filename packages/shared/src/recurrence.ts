/**
 * How far ahead a recurring rule with no end date is materialised.
 *
 * "No end date" cannot mean "forever": the occurrences are ordinary
 * transactions (see `docs/recurrency-design.md` §2.5), so an unbounded rule
 * would be an unbounded number of rows. Instead each frequency materialises a
 * fixed batch up front, and the user tops it up when they want more — which is
 * why the form has to say so rather than quietly capping them.
 */

export type RecurrenceFrequency =
    | 'daily'
    | 'weekly'
    | 'monthly'
    | 'yearly'
    | 'customDays'

/** How far a batch reaches, in whatever unit reads best for that batch. */
export type RecurrenceSpan =
    | { unit: 'days'; value: number }
    | { unit: 'months'; value: number }
    | { unit: 'years'; value: number }

export type RecurrenceHorizon = {
    /** Movements created up front for a rule with no end date. */
    count: number
    /** Roughly how far those movements reach. */
    span: RecurrenceSpan
}

/** Mean Gregorian month, so a day count converts without drifting over years. */
const DAYS_PER_MONTH = 365.2425 / 12

/**
 * The batch size for "every X days", picked from the cadence X resembles: a
 * few days behaves like daily, a couple of weeks like weekly, and so on. The
 * bands are half-open upwards — 7 is already weekly-ish, 365 already yearly.
 */
export function customDaysCount(dayInterval: number): number {
    const interval = Math.max(1, Math.floor(dayInterval))
    if (interval < 7) return 500
    if (interval < 30) return 100
    if (interval < 365) return 48
    return 20
}

/** Converts a total number of days into the coarsest unit that stays honest. */
function spanFromDays(days: number): RecurrenceSpan {
    const months = Math.round(days / DAYS_PER_MONTH)
    if (months >= 24) return { unit: 'years', value: Math.round(months / 12) }
    return { unit: 'months', value: months }
}

/**
 * The batch a rule with no end date materialises.
 *
 * `dayInterval` is only read for `customDays`; the other frequencies have a
 * fixed batch. The spans of the fixed ones are exact by construction (48
 * months *is* 4 years); the computed ones are rounded, which is why the copy
 * that renders them hedges.
 */
export function recurrenceHorizon(
    frequency: RecurrenceFrequency,
    dayInterval?: number,
): RecurrenceHorizon {
    switch (frequency) {
        case 'daily':
            return { count: 500, span: { unit: 'days', value: 500 } }
        case 'weekly':
            // 100 weeks — 700 days, just under two years.
            return { count: 100, span: { unit: 'months', value: 23 } }
        case 'monthly':
            return { count: 48, span: { unit: 'years', value: 4 } }
        case 'yearly':
            return { count: 20, span: { unit: 'years', value: 20 } }
        case 'customDays': {
            const interval = Math.max(1, Math.floor(dayInterval ?? 1))
            const count = customDaysCount(interval)
            return { count, span: spanFromDays(count * interval) }
        }
    }
}

/** Days in a given local month. Day 0 of the next month is the last of this. */
function daysInMonth(year: number, monthIndex: number): number {
    return new Date(year, monthIndex + 1, 0).getDate()
}

/**
 * The date of the `index`-th occurrence of a rule anchored at `anchorMs`
 * (index 0 *is* the anchor).
 *
 * Two rules, both from `docs/recurrency-design.md` §2.3:
 *
 * 1. **Every occurrence is projected from the anchor, never from the previous
 *    one.** Stepping month by month would let a February clipped to the 28th
 *    drag the error forward and leave March on the 28th too.
 * 2. **An anchor that falls on the last day of its month means "last day of
 *    the month".** So 31 Jan monthly gives 28/29 Feb, 31 Mar, 30 Apr — not the
 *    30th forever after the first short month. An anchor that is not the last
 *    day keeps its day number and is clipped only where the month is shorter.
 *
 * All arithmetic is on local calendar components, so a DST boundary moves the
 * instant but never the calendar day or the wall-clock time.
 */
export function occurrenceDateMs(
    anchorMs: number,
    frequency: RecurrenceFrequency,
    index: number,
    dayInterval = 1,
): number {
    const anchor = new Date(anchorMs)
    const year = anchor.getFullYear()
    const month = anchor.getMonth()
    const day = anchor.getDate()
    const time: [number, number, number, number] = [
        anchor.getHours(),
        anchor.getMinutes(),
        anchor.getSeconds(),
        anchor.getMilliseconds(),
    ]

    const byDays = (step: number) =>
        new Date(year, month, day + index * step, ...time).getTime()

    switch (frequency) {
        case 'daily':
            return byDays(1)
        case 'weekly':
            return byDays(7)
        case 'customDays':
            return byDays(Math.max(1, Math.floor(dayInterval)))
        case 'monthly':
        case 'yearly': {
            const monthStep = frequency === 'monthly' ? index : index * 12
            const absolute = month + monthStep
            const targetYear = year + Math.floor(absolute / 12)
            const targetMonth = ((absolute % 12) + 12) % 12
            const lastDayHere = daysInMonth(year, month)
            const lastDayThere = daysInMonth(targetYear, targetMonth)
            const targetDay =
                day === lastDayHere ? lastDayThere : Math.min(day, lastDayThere)
            return new Date(
                targetYear,
                targetMonth,
                targetDay,
                ...time,
            ).getTime()
        }
    }
}

/**
 * How many occurrences a rule produces, capped by its horizon.
 *
 * An end date is inclusive and always wins when it is the tighter of the two:
 * a rule that ends next month does not get the open-ended batch. Without one
 * the horizon is the whole answer.
 */
export function occurrenceCount(
    anchorMs: number,
    frequency: RecurrenceFrequency,
    endDateMs: number | null,
    dayInterval = 1,
): number {
    const horizon = recurrenceHorizon(frequency, dayInterval).count
    if (endDateMs === null) return horizon
    let count = 0
    while (count < horizon) {
        const next = occurrenceDateMs(anchorMs, frequency, count, dayInterval)
        if (next > endDateMs) break
        count += 1
    }
    return count
}
