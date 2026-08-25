// The TS half of the cross-language calculator parity suite. The same fixture
// table runs against the Dart mirrors in
// apps/native/test/voice/calc_fixtures_test.dart — a behavioural change on
// one side fails the other side's run until both are updated together.

import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { type CalcStep, runCalculate } from '../src/tools/calc'
import { type DateCalcArgs, runCalculateDate } from '../src/tools/date-calc'

type LocalDate = {
    year: number
    month: number
    day: number
    hour?: number
    minute?: number
    second?: number
    millisecond?: number
}

type Fixtures = {
    now: Required<LocalDate>
    calculate: { steps: CalcStep[]; values?: number[]; throws?: boolean }[]
    calculateDate: {
        args: DateCalcArgs
        expect?: Record<string, unknown>
        throws?: boolean
    }[]
}

const fixtures: Fixtures = JSON.parse(
    readFileSync(
        resolve(import.meta.dirname, '../src/tools/calc-fixtures.json'),
        'utf8',
    ),
)

const now = new Date(
    fixtures.now.year,
    fixtures.now.month - 1,
    fixtures.now.day,
    fixtures.now.hour,
    fixtures.now.minute,
    fixtures.now.second,
    fixtures.now.millisecond,
)

describe('runCalculate fixtures', () => {
    for (const c of fixtures.calculate) {
        const label = c.steps.map((s) => s.expression).join(' ; ') || '(empty)'
        it(label, () => {
            if (c.throws) {
                expect(() => runCalculate(c.steps)).toThrow()
                return
            }
            if (!c.values) throw new Error('fixture needs values or throws')
            // Both engines compute in IEEE 754 doubles — results are exact.
            expect(runCalculate(c.steps).map((s) => s.value)).toEqual(c.values)
        })
    }
})

describe('runCalculateDate fixtures', () => {
    for (const c of fixtures.calculateDate) {
        it(JSON.stringify(c.args), () => {
            if (c.throws) {
                expect(() => runCalculateDate(c.args, now)).toThrow()
                return
            }
            if (!c.expect) throw new Error('fixture needs expect or throws')
            expect(runCalculateDate(c.args, now)).toEqual(c.expect)
        })
    }
})
