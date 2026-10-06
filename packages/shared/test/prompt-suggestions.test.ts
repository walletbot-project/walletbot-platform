// The TS half of the prompt-suggestions parity suite. The same fixture table
// runs against the Dart port in
// apps/native/test/voice/prompt_suggestions_test.dart. A behavioural change on
// one side fails the other side's run until both are updated together.

import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import {
    generatePromptSuggestions,
    mulberry32,
    niceAmountCents,
    PROMPT_SUGGESTION_COUNT,
    type PromptSuggestion,
    type PromptSuggestionKind,
    promptSuggestionSetKey,
    type SuggestionData,
} from '../src/prompt-suggestions'

type Fixtures = {
    datasets: Record<string, SuggestionData>
    cases: {
        name: string
        dataset: string
        seed: number
        previousFrom?: string
        expect: PromptSuggestion[]
    }[]
    mulberry32: { seed: number; values: number[] }
    niceAmountCents: [number, number][]
}

const fixtures: Fixtures = JSON.parse(
    readFileSync(
        resolve(import.meta.dirname, '../src/prompt-suggestions-fixtures.json'),
        'utf8',
    ),
)

const ACTIONS = new Set<PromptSuggestionKind>([
    'logExpense',
    'transfer',
    'logIncome',
])

describe('prompt suggestion fixtures', () => {
    it('mulberry32', () => {
        const random = mulberry32(fixtures.mulberry32.seed)
        expect(fixtures.mulberry32.values.map(() => random())).toEqual(
            fixtures.mulberry32.values,
        )
    })

    it.each(fixtures.niceAmountCents)('niceAmountCents(%d)', (cents, nice) => {
        expect(niceAmountCents(cents)).toBe(nice)
    })

    for (const c of fixtures.cases) {
        it(c.name, () => {
            const previousCase = fixtures.cases.find(
                (other) => other.name === c.previousFrom,
            )
            const result = generatePromptSuggestions(
                fixtures.datasets[c.dataset],
                {
                    random: mulberry32(c.seed),
                    previous: previousCase
                        ? promptSuggestionSetKey(previousCase.expect)
                        : undefined,
                },
            )
            expect(result).toEqual(c.expect)
        })
    }
})

describe('prompt suggestion rules', () => {
    const rich = fixtures.datasets.rich
    const draws = Array.from({ length: 300 }, (_, seed) =>
        generatePromptSuggestions(rich, { random: mulberry32(seed) }),
    )

    it('always fills the row and never repeats a template', () => {
        for (const draw of draws) {
            expect(draw).toHaveLength(PROMPT_SUGGESTION_COUNT)
            expect(new Set(draw.map((s) => s.kind)).size).toBe(draw.length)
        }
    })

    it('mixes recording something with asking something', () => {
        for (const draw of draws) {
            expect(draw.some((s) => ACTIONS.has(s.kind))).toBe(true)
            expect(draw.some((s) => !ACTIONS.has(s.kind))).toBe(true)
        }
    })

    it('mentions one category at most twice', () => {
        for (const draw of draws) {
            const counts = new Map<string, number>()
            for (const s of draw) {
                if (s.category)
                    counts.set(s.category, (counts.get(s.category) ?? 0) + 1)
            }
            for (const count of counts.values()) {
                expect(count).toBeLessThanOrEqual(2)
            }
        }
    })

    it('only names active entities and used tags', () => {
        const names = new Set([
            ...rich.accounts.map((a) => a.name),
            ...rich.categories.map((c) => c.name),
            ...rich.tags.filter((t) => t.usageCount > 0).map((t) => t.name),
        ])
        for (const s of draws.flat()) {
            for (const name of [s.category, s.account, s.toAccount, s.tag]) {
                if (name !== undefined) expect(names.has(name)).toBe(true)
            }
        }
    })

    it('changes the set between consecutive opens', () => {
        let previous = ''
        for (let seed = 0; seed < 100; seed++) {
            const draw = generatePromptSuggestions(rich, {
                random: mulberry32(seed),
                previous,
            })
            const key = promptSuggestionSetKey(draw)
            expect(key).not.toBe(previous)
            previous = key
        }
    })

    it('always includes exactly one Home widget suggestion', () => {
        for (const dataset of Object.values(fixtures.datasets)) {
            for (let seed = 0; seed < 100; seed++) {
                const draw = generatePromptSuggestions(dataset, {
                    random: mulberry32(seed),
                })
                expect(
                    draw.filter((s) => s.kind === 'homeWidget'),
                ).toHaveLength(1)
            }
        }
    })

    it('offers starter suggestions when there is no usable history', () => {
        const starters = new Set<PromptSuggestionKind>([
            'whatCanYouDo',
            'createCashAccount',
            'setupCategories',
            'howToLogExpense',
        ])
        const draw = generatePromptSuggestions(fixtures.datasets.newUser, {
            random: mulberry32(1),
        })
        expect(draw).toHaveLength(PROMPT_SUGGESTION_COUNT)
        expect(draw.filter((s) => starters.has(s.kind))).toHaveLength(4)
        expect(draw).toContainEqual({ kind: 'homeWidget' })
    })
})
