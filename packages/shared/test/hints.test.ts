import { describe, expect, it } from 'vitest'
import { AGENT_SKILLS_BY_SLUG } from '../src/agent-skills'
import { TOOL_HINTS, TOOL_NAMES, withToolHint } from '../src/tools'

describe('TOOL_HINTS', () => {
    it('only hints tools that exist', () => {
        for (const name of Object.keys(TOOL_HINTS)) {
            expect(TOOL_NAMES).toContain(name)
        }
    })

    it('points at a skill that is actually bundled', () => {
        for (const hint of Object.values(TOOL_HINTS)) {
            expect(hint).toContain('suggesting-features')
        }
        expect(AGENT_SKILLS_BY_SLUG.has('suggesting-features')).toBe(true)
    })

    it('covers the moments the three suggestable features arise', () => {
        expect(Object.keys(TOOL_HINTS).sort()).toEqual([
            'createAccount',
            'createCategory',
            'createTag',
            'getAccountBalance',
            'summarizeTransactions',
        ])
    })
})

describe('withToolHint', () => {
    it('appends the hint to a successful result', () => {
        const result = withToolHint('summarizeTransactions', {
            ok: true,
            rows: [],
        })
        expect(result.hint).toBe(TOOL_HINTS.summarizeTransactions)
        expect(result.rows).toEqual([])
    })

    it('leaves failures alone — a failed call is no moment to pitch', () => {
        const failure = { ok: false, error: 'Account not found' }
        expect(withToolHint('getAccountBalance', failure)).toEqual(failure)
    })

    it('leaves unhinted tools alone', () => {
        const result = { ok: true, id: 'abc' }
        expect(withToolHint('deleteTransaction', result)).toEqual(result)
    })

    it('never overwrites a hint the executor set itself', () => {
        const result = withToolHint('createTag', { ok: true, hint: 'mine' })
        expect(result.hint).toBe('mine')
    })
})
