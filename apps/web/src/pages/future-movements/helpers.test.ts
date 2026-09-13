import { describe, expect, it } from 'vitest'
import { dateInputValue, timeInputValue } from '../activity/helpers'
import { resolveMovementDateEdit } from './helpers'

const date = BigInt(new Date(2027, 0, 31, 12, 5, 48, 209).getTime())
const original = { date, dateConfirmed: false, timeStatus: 'none' as const }

describe('future movement date edits', () => {
    it('does not re-anchor a series when only its amount or cadence changes', () => {
        const edit = resolveMovementDateEdit(
            original,
            dateInputValue(date),
            timeInputValue(date),
        )
        expect(edit).toEqual(original)
        expect(edit.date !== original.date).toBe(false)
    })

    it('retains approximate time confidence on an unchanged form', () => {
        const approximate = {
            ...original,
            timeStatus: 'approximation' as const,
        }
        expect(
            resolveMovementDateEdit(
                approximate,
                dateInputValue(date),
                timeInputValue(date),
            ),
        ).toEqual(approximate)
    })

    it('confirms only the calendar date when that control changes', () => {
        const edit = resolveMovementDateEdit(
            original,
            '2027-02-01',
            timeInputValue(date),
        )
        expect(edit).toEqual({
            date: BigInt(new Date(2027, 1, 1, 12, 5).getTime()),
            dateConfirmed: true,
            timeStatus: 'none',
        })
    })

    it('confirms only the time when that control changes', () => {
        const edit = resolveMovementDateEdit(
            original,
            dateInputValue(date),
            '13:00',
        )
        expect(edit).toEqual({
            date: BigInt(new Date(2027, 0, 31, 13).getTime()),
            dateConfirmed: false,
            timeStatus: 'confirmed',
        })
    })
})
