import { describe, expect, it } from 'vitest'
import {
    isBalanceWidgetType,
    monthCloseAsOfMs,
    WIDGET_TYPES,
} from '../src/dashboard/widgets'

describe('isBalanceWidgetType', () => {
    it('is the balance card and the balance comparison, nothing else', () => {
        expect(WIDGET_TYPES.filter(isBalanceWidgetType)).toEqual([
            'balance',
            'balance_comparison',
        ])
    })

    it('rejects a type written by a newer client', () => {
        expect(isBalanceWidgetType('future_type')).toBe(false)
    })
})

describe('monthCloseAsOfMs', () => {
    it('is the local midnight that starts the month', () => {
        expect(monthCloseAsOfMs(new Date(2026, 9, 3, 15, 30))).toBe(
            new Date(2026, 9, 1).getTime(),
        )
        expect(monthCloseAsOfMs(new Date(2026, 9, 1))).toBe(
            new Date(2026, 9, 1).getTime(),
        )
    })

    it('crosses the year on the first of January', () => {
        expect(monthCloseAsOfMs(new Date(2027, 0, 1, 0, 5))).toBe(
            new Date(2027, 0, 1).getTime(),
        )
    })
})
