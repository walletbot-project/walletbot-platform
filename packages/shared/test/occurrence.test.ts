import { describe, expect, it } from 'vitest'
import { OCCURRENCE_BUCKET_MS, pastCutoffMs } from '../src/occurrence'

describe('occurrence cutoff', () => {
    it('is the end of the 20-minute block', () => {
        expect(OCCURRENCE_BUCKET_MS).toBe(20 * 60 * 1000)
        // 14:07 sits in the 14:00–14:20 block, so the boundary is 14:20.
        expect(pastCutoffMs(new Date('2026-09-03T14:07:31.500Z'))).toBe(
            new Date('2026-09-03T14:20:00.000Z').getTime(),
        )
        expect(pastCutoffMs(new Date('2026-09-03T14:39:59.999Z'))).toBe(
            new Date('2026-09-03T14:40:00.000Z').getTime(),
        )
    })

    it('rounds up, never down', () => {
        // Load-bearing: the cutoff is an exclusive upper bound, so rounding
        // down would put a movement recorded *right now* above it and make the
        // expense the user just entered vanish from Activity.
        const now = new Date('2026-09-03T14:07:31.500Z')
        expect(pastCutoffMs(now)).toBeGreaterThan(now.getTime())
    })

    it('moves past a `now` that sits exactly on a boundary', () => {
        // The old day cutoff was always the *next* midnight, never "today at
        // 00:00"; same rule here, or a movement dated exactly now would read
        // as not yet happened.
        const boundary = new Date('2026-09-03T14:20:00.000Z')
        expect(pastCutoffMs(boundary)).toBe(
            new Date('2026-09-03T14:40:00.000Z').getTime(),
        )
    })

    it('is the same number everywhere at the same instant', () => {
        // Cut from the epoch, not from a local day: every client in the world
        // sends the same argument inside a block, so they share one cache
        // entry. This is what a local-midnight boundary could not do.
        const instant = new Date('2026-09-03T14:07:31.500Z')
        expect(pastCutoffMs(instant) % OCCURRENCE_BUCKET_MS).toBe(0)
    })

    it('advances exactly once per block', () => {
        const start = new Date('2026-09-03T14:00:00.000Z').getTime()
        const seen = new Set<number>()
        // Every minute of an hour: three distinct cutoffs, not sixty.
        for (let minute = 0; minute < 60; minute += 1) {
            seen.add(pastCutoffMs(new Date(start + minute * 60_000)))
        }
        expect(seen.size).toBe(3)
    })
})
