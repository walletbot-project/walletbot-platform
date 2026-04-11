import { calc } from 'a-calc'

/**
 * Safely evaluate a math expression using a-calc (no eval).
 * Returns the result as a string with precision.
 *
 * Supports: +, -, *, /, parentheses, decimals.
 * Variables can be passed as the second argument.
 *
 * @example
 * safeCalc("100 * 1400")           // "140000"
 * safeCalc("a / b", { a: 100, b: 3 })  // "33.333333333333"
 * safeCalc("0.1 + 0.2")            // "0.3"
 */
export function safeCalc(
    expression: string,
    variables?: Record<string, number | string>,
): string {
    const result = calc(expression, variables)
    if (
        result === '-' ||
        result === '' ||
        result === 'NaN' ||
        result === 'Infinity'
    ) {
        throw new Error(`Invalid calculation: ${expression}`)
    }
    return result
}

/**
 * Convert an amount between currencies given an exchange rate.
 * Uses precision arithmetic.
 *
 * @example
 * convertCurrency(100_00, 1400) // 14000000 (100 USD * 1400 = 140,000 ARS, in cents)
 */
export function convertCurrency(amountCents: number, rate: number): number {
    const result = calc('a * b', { a: amountCents, b: rate })
    return Math.round(Number(result))
}

/**
 * Format a number with a-calc's formatting.
 * @example
 * formatCalcResult("1234567.89", "=2,") // "1,234,567.89"
 */
export function formatCalcResult(value: string, format: string): string {
    return calc(`${value} | ${format}`)
}
