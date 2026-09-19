import { describe, expect, it } from 'vitest'
import {
    customDaysCount,
    maxOccurrenceCount,
    OCCURRENCE_CAP_MULTIPLIER,
    occurrenceCount,
    occurrenceDateMs,
    recurrenceHorizon,
} from '../src/recurrence'

/** Local-midnight helper — the projection works on calendar components. */
function at(year: number, month: number, day: number, hour = 0): number {
    return new Date(year, month - 1, day, hour).getTime()
}

function project(
    anchor: number,
    frequency: Parameters<typeof occurrenceDateMs>[1],
    howMany: number,
    dayInterval = 1,
): string[] {
    return Array.from({ length: howMany }, (_, index) => {
        const d = new Date(
            occurrenceDateMs(anchor, frequency, index, dayInterval),
        )
        const mm = `${d.getMonth() + 1}`.padStart(2, '0')
        const dd = `${d.getDate()}`.padStart(2, '0')
        return `${d.getFullYear()}-${mm}-${dd}`
    })
}

describe('month-end inference (docs/recurrency-design.md §2.3)', () => {
    it('treats a last-day anchor as "last day of the month"', () => {
        expect(project(at(2026, 1, 31), 'monthly', 6)).toEqual([
            '2026-01-31',
            '2026-02-28',
            '2026-03-31',
            '2026-04-30',
            '2026-05-31',
            '2026-06-30',
        ])
    })

    it('keeps the day number when the anchor is not the last day', () => {
        expect(project(at(2026, 1, 30), 'monthly', 4)).toEqual([
            '2026-01-30',
            '2026-02-28',
            '2026-03-30',
            '2026-04-30',
        ])
    })

    it('does not drift: a clipped February never shortens March', () => {
        // Projecting from the previous occurrence would give 28 Mar here.
        expect(project(at(2026, 1, 31), 'monthly', 3)[2]).toBe('2026-03-31')
    })

    it('uses 29 February in a leap year for a last-day anchor', () => {
        expect(project(at(2027, 1, 31), 'monthly', 2)[1]).toBe('2027-02-28')
        expect(project(at(2028, 1, 31), 'monthly', 2)[1]).toBe('2028-02-29')
    })

    it('clamps a 29 February anchor to 28 in non-leap years', () => {
        expect(project(at(2028, 2, 29), 'yearly', 5)).toEqual([
            '2028-02-29',
            '2029-02-28',
            '2030-02-28',
            '2031-02-28',
            '2032-02-29',
        ])
    })
})

describe('day-based frequencies', () => {
    it('steps daily across a month boundary', () => {
        expect(project(at(2026, 1, 30), 'daily', 4)).toEqual([
            '2026-01-30',
            '2026-01-31',
            '2026-02-01',
            '2026-02-02',
        ])
    })

    it('steps weekly', () => {
        expect(project(at(2026, 1, 1), 'weekly', 3)).toEqual([
            '2026-01-01',
            '2026-01-08',
            '2026-01-15',
        ])
    })

    it('steps by the custom interval', () => {
        expect(project(at(2026, 1, 1), 'customDays', 3, 45)).toEqual([
            '2026-01-01',
            '2026-02-15',
            '2026-04-01',
        ])
    })

    it('keeps the wall-clock time rather than the instant', () => {
        const anchor = at(2026, 1, 1, 9)
        const tenth = new Date(occurrenceDateMs(anchor, 'daily', 200))
        expect(tenth.getHours()).toBe(9)
    })
})

describe('open-ended horizons', () => {
    it('matches the agreed batch per frequency', () => {
        expect(recurrenceHorizon('daily')).toEqual({
            count: 500,
            span: { unit: 'days', value: 500 },
        })
        expect(recurrenceHorizon('weekly')).toEqual({
            count: 100,
            span: { unit: 'months', value: 23 },
        })
        expect(recurrenceHorizon('monthly')).toEqual({
            count: 48,
            span: { unit: 'years', value: 4 },
        })
        expect(recurrenceHorizon('yearly')).toEqual({
            count: 20,
            span: { unit: 'years', value: 20 },
        })
    })

    it('picks the custom batch from the band the interval falls in', () => {
        expect(customDaysCount(1)).toBe(500)
        expect(customDaysCount(6)).toBe(500)
        expect(customDaysCount(7)).toBe(100)
        expect(customDaysCount(29)).toBe(100)
        expect(customDaysCount(30)).toBe(48)
        expect(customDaysCount(364)).toBe(48)
        expect(customDaysCount(365)).toBe(20)
        expect(customDaysCount(400)).toBe(20)
    })

    it('spans the custom batch in months or years', () => {
        // 500 x 3 days = 1500 days.
        expect(recurrenceHorizon('customDays', 3).span).toEqual({
            unit: 'years',
            value: 4,
        })
        // 500 x 1 day = 500 days, under two years, so months.
        expect(recurrenceHorizon('customDays', 1).span).toEqual({
            unit: 'months',
            value: 16,
        })
    })
})

describe('occurrence count', () => {
    it('is the horizon when the rule is open-ended', () => {
        expect(occurrenceCount(at(2026, 1, 1), 'monthly', null)).toBe(48)
    })

    it('stops at an inclusive end date', () => {
        // Jan, Feb, Mar — the end date lands exactly on the third.
        expect(
            occurrenceCount(at(2026, 1, 15), 'monthly', at(2026, 3, 15)),
        ).toBe(3)
    })

    it('excludes an end date that falls between occurrences', () => {
        expect(
            occurrenceCount(at(2026, 1, 15), 'monthly', at(2026, 3, 14)),
        ).toBe(2)
    })

    it('creates every occurrence up to a distant end date', () => {
        // The batch is only there to give an *open-ended* rule a finite size.
        // "Monthly until 2036" means 120 movements, not the first 48 of them.
        expect(
            occurrenceCount(at(2026, 1, 15), 'monthly', at(2036, 1, 15)),
        ).toBe(121)
        expect(
            occurrenceCount(at(2026, 1, 15), 'monthly', at(2036, 1, 14)),
        ).toBe(120)
    })

    it('counts a long day-based series exactly', () => {
        // 2028 is a leap year: 2026-01-01 to 2030-01-01 is 1461 days, so 1462
        // daily occurrences counting both ends.
        expect(occurrenceCount(at(2026, 1, 1), 'daily', at(2030, 1, 1))).toBe(
            1462,
        )
        // Same span, weekly: every 7th day of those 1461.
        expect(occurrenceCount(at(2026, 1, 1), 'weekly', at(2030, 1, 1))).toBe(
            Math.floor(1461 / 7) + 1,
        )
        // And "every 10 days" honours its own interval.
        expect(
            occurrenceCount(at(2026, 1, 1), 'customDays', at(2030, 1, 1), 10),
        ).toBe(Math.floor(1461 / 10) + 1)
    })

    it('counts a yearly series past its open-ended batch', () => {
        expect(occurrenceCount(at(2026, 3, 1), 'yearly', at(2076, 3, 1))).toBe(
            51,
        )
    })

    it('agrees with stepping one occurrence at a time', () => {
        // The count is found by binary search; this is the naive walk it
        // replaced, kept as the oracle.
        const anchor = at(2026, 1, 31, 9)
        for (const [frequency, end] of [
            ['daily', at(2026, 4, 17)],
            ['weekly', at(2027, 2, 2)],
            ['monthly', at(2031, 7, 15)],
            ['yearly', at(2044, 1, 30)],
        ] as const) {
            let walked = 0
            while (occurrenceDateMs(anchor, frequency, walked) <= end) {
                walked += 1
            }
            expect(occurrenceCount(anchor, frequency, end)).toBe(walked)
        }
    })

    it('is zero when the end date precedes the anchor', () => {
        expect(
            occurrenceCount(at(2026, 1, 15), 'monthly', at(2025, 12, 1)),
        ).toBe(0)
    })
})

describe('per-call cap', () => {
    it('is five open-ended batches of the frequency', () => {
        expect(OCCURRENCE_CAP_MULTIPLIER).toBe(5)
        expect(maxOccurrenceCount('daily')).toBe(2500)
        expect(maxOccurrenceCount('weekly')).toBe(500)
        expect(maxOccurrenceCount('monthly')).toBe(240)
        expect(maxOccurrenceCount('yearly')).toBe(100)
        expect(maxOccurrenceCount('customDays', 10)).toBe(500)
    })

    it('is what "daily until 2050" runs into', () => {
        const total = occurrenceCount(at(2026, 1, 1), 'daily', at(2050, 1, 1))
        expect(total).toBeGreaterThan(maxOccurrenceCount('daily'))
        // A bounded series inside the cap is untouched by it.
        expect(
            occurrenceCount(at(2026, 1, 15), 'monthly', at(2035, 12, 31)),
        ).toBeLessThanOrEqual(maxOccurrenceCount('monthly'))
    })
})
