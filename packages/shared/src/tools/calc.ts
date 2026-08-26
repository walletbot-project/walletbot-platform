// Numeric evaluation for the `calculate` tool.
//
// The native (Dart) side mirrors this in apps/native/lib/voice/tool_calc.dart
// — both must expose the same accept/reject surface and produce identical
// results. Parity is locked by calc-fixtures.json, run by
// packages/shared/test/calc-fixtures.test.ts (TS) and
// apps/native/test/voice/calc_fixtures_test.dart (Dart).
//
// The syntax is deliberately the least common denominator of the two engines
// (mathjs on web, math_expressions on native): numbers, + - * / ^,
// parentheses, previously bound step names, and the CALC_FUNCTIONS below.
// Everything else — assignments, '%', implicit multiplication, scientific
// notation, matrices, strings, units — is rejected by the shared guard BEFORE
// the engine sees it, so engine-specific extras can never leak through on one
// platform only.

import { all, create } from 'mathjs/number'

/** The only callable functions. Both platforms reject anything else. */
export const CALC_FUNCTIONS = [
    'abs',
    'ceil',
    'floor',
    'max',
    'min',
    'pow',
    'round',
    'sqrt',
] as const

export const CALC_MAX_STEPS = 20
const MAX_EXPRESSION_LENGTH = 200

export type CalcStep = { expression: string; name?: string }
export type CalcStepResult = {
    expression: string
    name?: string
    value: number
}

// The whole allowed alphabet. Notably absent: '=' (assignments), '%'
// (modulo semantics differ between engines), '[' and quotes (matrices,
// strings), ';' (multi-statement — steps are the multi-statement mechanism).
const ALLOWED_CHARS = /^[0-9a-zA-Z_+\-*/^().,\s]+$/
const IDENTIFIER = /[a-zA-Z_][a-zA-Z0-9_]*/g
const VALID_NAME = /^[a-zA-Z_][a-zA-Z0-9_]*$/
// mathjs supports implicit multiplication ("2(3+1)", "2x") and scientific
// notation ("1e3"); the Dart engine does not. Reject all of it everywhere.
const IMPLICIT_MULTIPLICATION = [
    /[0-9)]\s*\(/,
    /\)\s*[0-9a-zA-Z_]/,
    /[0-9]\s*[a-zA-Z_]/,
]

function isCalcFunction(identifier: string): boolean {
    return (CALC_FUNCTIONS as readonly string[]).includes(identifier)
}

/**
 * Validates one expression against the shared syntax contract. Throws with a
 * model-readable message on violation. `boundNames` are the step names bound
 * so far.
 */
export function validateCalcExpression(
    expression: string,
    boundNames: ReadonlySet<string>,
): void {
    if (expression.length === 0) {
        throw new Error('Expression is empty')
    }
    if (expression.length > MAX_EXPRESSION_LENGTH) {
        throw new Error(
            `Expression is too long (max ${MAX_EXPRESSION_LENGTH} characters)`,
        )
    }
    if (!ALLOWED_CHARS.test(expression)) {
        throw new Error(
            `Unsupported syntax in "${expression}": only numbers, + - * / ^, parentheses, commas, step names and the functions ${CALC_FUNCTIONS.join(', ')} are allowed`,
        )
    }
    for (const pattern of IMPLICIT_MULTIPLICATION) {
        if (pattern.test(expression)) {
            throw new Error(
                `Write multiplication explicitly with * in "${expression}"`,
            )
        }
    }
    for (const match of expression.matchAll(IDENTIFIER)) {
        const identifier = match[0]
        const rest = expression.slice(match.index + identifier.length)
        if (/^\s*\(/.test(rest)) {
            if (!isCalcFunction(identifier)) {
                throw new Error(
                    `Unknown function "${identifier}". Available: ${CALC_FUNCTIONS.join(', ')}`,
                )
            }
        } else if (!boundNames.has(identifier)) {
            throw new Error(
                `Unknown name "${identifier}". Bind it with a previous step's "name" first.`,
            )
        }
    }
}

// Lazily created so importing the shared barrel (e.g. from the backend) does
// not pay the instance construction at module load. The number-only bundle
// has no Complex/Matrix/Unit machinery; the guard above further restricts
// what can reach it.
let mathInstance: ReturnType<typeof create> | null = null

function getMath(): ReturnType<typeof create> {
    mathInstance ??= create(all)
    return mathInstance
}

function evaluateExpression(
    expression: string,
    scope: Map<string, number>,
): number {
    let raw: unknown
    try {
        raw = getMath().evaluate(expression, scope) as unknown
    } catch (error) {
        const detail = error instanceof Error ? error.message : String(error)
        throw new Error(`Could not evaluate "${expression}": ${detail}`)
    }
    if (typeof raw !== 'number' || !Number.isFinite(raw)) {
        throw new Error(
            `"${expression}" did not produce a finite number (check for division by zero)`,
        )
    }
    return raw
}

/**
 * Runs the steps in order; each step may bind its result to a name for later
 * steps. Returns one result per step. Throws on the first invalid step.
 */
export function runCalculate(steps: readonly CalcStep[]): CalcStepResult[] {
    if (steps.length === 0) {
        throw new Error('At least one step is required')
    }
    if (steps.length > CALC_MAX_STEPS) {
        throw new Error(`Too many steps (max ${CALC_MAX_STEPS})`)
    }
    const scope = new Map<string, number>()
    const results: CalcStepResult[] = []
    for (const step of steps) {
        const expression = step.expression.trim()
        validateCalcExpression(expression, new Set(scope.keys()))
        if (step.name !== undefined) {
            if (!VALID_NAME.test(step.name)) {
                throw new Error(`Invalid step name "${step.name}"`)
            }
            if (isCalcFunction(step.name)) {
                throw new Error(
                    `Step name "${step.name}" collides with a function name`,
                )
            }
        }
        const value = evaluateExpression(expression, scope)
        if (step.name !== undefined) {
            scope.set(step.name, value)
            results.push({ expression, name: step.name, value })
        } else {
            results.push({ expression, value })
        }
    }
    return results
}
