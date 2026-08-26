import { describe, expect, it } from 'vitest'
import { TOOL_HINTS, withToolHint } from '../src/tools'

describe('withToolHint', () => {
    it('appends the hint to a successful result', () => {
        const result = withToolHint('summarizeTransactions', { ok: true })
        expect(result.hint).toBe(TOOL_HINTS.summarizeTransactions)
    })

    it('leaves failures alone — a failed call is no moment to pitch', () => {
        const failure = { ok: false, error: 'Account not found' }
        expect(withToolHint('getAccountBalance', failure)).toEqual(failure)
    })

    it('leaves unhinted tools alone', () => {
        const result = { ok: true, id: 'abc' }
        expect(withToolHint('deleteTransaction', result)).toEqual(result)
    })
})
