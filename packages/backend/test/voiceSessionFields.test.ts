// Unit tests for the session-patch predicate — outside convex/ so the Convex
// bundler never sees them. Everything under test is pure (no ctx, no db).

import { describe, expect, it } from 'vitest'
import {
    type SessionSnapshot,
    sessionFieldsChanged,
} from '../convex/v1/voice/utils'

const base: SessionSnapshot = {
    model: 'gemini-live',
    status: 'active',
    startedAt: 1n,
    updatedAt: 2n,
    endedExplicitly: false,
}

describe('sessionFieldsChanged', () => {
    it('an identical payload is not a change', () => {
        // This is the case that matters: concurrent batches replicating one
        // session all carry the same payload, and the whole point is that
        // they stop writing the document once the first has landed.
        expect(sessionFieldsChanged(base, { ...base })).toBe(false)
    })

    it('compares int64 fields by value, not identity', () => {
        // A fresh bigint from the wire is never the same object as the stored
        // one, so an identity comparison would report every batch as changed
        // and put the conflict straight back.
        expect(
            sessionFieldsChanged(base, { ...base, updatedAt: BigInt(2) }),
        ).toBe(false)
        expect(sessionFieldsChanged(base, { ...base, updatedAt: 3n })).toBe(
            true,
        )
    })

    it('catches the fields a live session actually moves', () => {
        expect(sessionFieldsChanged(base, { ...base, status: 'ended' })).toBe(
            true,
        )
        expect(
            sessionFieldsChanged(base, { ...base, endedExplicitly: true }),
        ).toBe(true)
        expect(sessionFieldsChanged(base, { ...base, endedAt: 9n })).toBe(true)
    })

    it('an absent endedAt on both sides is not a change', () => {
        // A row stored before the session ended has no endedAt at all, and an
        // explicit undefined has to compare equal to it or every batch for a
        // live session would write.
        expect(
            sessionFieldsChanged(base, { ...base, endedAt: undefined }),
        ).toBe(false)
    })
})
