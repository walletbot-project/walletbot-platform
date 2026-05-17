// Shared pure helpers used by tool executors on web. The native (Dart) side
// must mirror these in Dart — keep this file the canonical reference.

/**
 * Converts a decimal user-facing amount to int64 cents.
 * `12.5` → `1250n`, `-3.07` → `-307n`, `0` → `0n`.
 *
 * Throws on NaN / Infinity / non-finite.
 */
export function parseAmountToCents(decimal: number): bigint {
    if (!Number.isFinite(decimal)) {
        throw new Error(`Invalid amount: ${decimal}`)
    }
    // Round to handle floating-point noise (e.g. 0.1 + 0.2 → 0.30000000000000004).
    const cents = Math.round(decimal * 100)
    return BigInt(cents)
}

/**
 * Parses an ISO date or a handful of natural-language English/Spanish phrases
 * to ms-epoch. Falls back to `Date.parse` for anything not recognized; throws
 * if that fails too.
 *
 * Supported natural phrases (case-insensitive):
 *  - "today" | "hoy"
 *  - "yesterday" | "ayer"
 *  - "tomorrow" | "mañana" | "manana"
 */
export function parseNaturalDate(
    input: string,
    now: Date = new Date(),
): bigint {
    const trimmed = input.trim().toLowerCase()

    const day = (offset: number) => {
        const d = new Date(now)
        d.setHours(0, 0, 0, 0)
        d.setDate(d.getDate() + offset)
        return BigInt(d.getTime())
    }

    if (trimmed === 'today' || trimmed === 'hoy') return day(0)
    if (trimmed === 'yesterday' || trimmed === 'ayer') return day(-1)
    if (trimmed === 'tomorrow' || trimmed === 'mañana' || trimmed === 'manana')
        return day(1)

    const parsed = Date.parse(input)
    if (Number.isNaN(parsed)) {
        throw new Error(`Unrecognized date: ${input}`)
    }
    return BigInt(parsed)
}

/** Optional version: returns undefined when input is undefined. */
export function parseOptionalDate(
    input: string | undefined,
    now?: Date,
): bigint | undefined {
    if (input === undefined) return undefined
    return parseNaturalDate(input, now)
}

/** Case-insensitive name match. Used by entity resolvers. */
export function normalizeName(name: string): string {
    return name.trim().toLocaleLowerCase()
}
