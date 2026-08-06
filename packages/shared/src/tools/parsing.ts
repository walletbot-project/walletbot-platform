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
 *  - "last Thursday" | "el jueves pasado"
 *  - "3 days ago" | "hace 3 días"
 */
export function parseNaturalDate(
    input: string,
    now: Date = new Date(),
): bigint {
    const trimmed = input.trim().toLowerCase()
    const normalized = trimmed.normalize('NFD').replace(/[\u0300-\u036f]/g, '')

    const day = (offset: number) => {
        const d = new Date(now)
        d.setHours(0, 0, 0, 0)
        d.setDate(d.getDate() + offset)
        return BigInt(d.getTime())
    }

    // Date-only ISO values represent a local calendar day. `Date.parse`
    // treats them as UTC midnight, which moves the transaction to the previous
    // day in negative UTC offsets such as Argentina.
    const isoDate = normalized.match(/^(\d{4})-(\d{2})-(\d{2})$/)
    if (isoDate) {
        const year = Number(isoDate[1])
        const month = Number(isoDate[2])
        const date = Number(isoDate[3])
        const localDate = new Date(year, month - 1, date)
        if (
            localDate.getFullYear() !== year ||
            localDate.getMonth() !== month - 1 ||
            localDate.getDate() !== date
        ) {
            throw new Error(`Unrecognized date: ${input}`)
        }
        return BigInt(localDate.getTime())
    }

    if (normalized === 'today' || normalized === 'hoy') return day(0)
    if (normalized === 'yesterday' || normalized === 'ayer') return day(-1)
    if (normalized === 'anteayer' || normalized === 'day before yesterday')
        return day(-2)
    if (normalized === 'tomorrow' || normalized === 'manana') return day(1)

    const daysAgo =
        normalized.match(/^hace\s+(\d+)\s+dias?$/) ??
        normalized.match(/^(\d+)\s+days?\s+ago$/)
    if (daysAgo) return day(-Number(daysAgo[1]))

    const weekdays: Record<string, number> = {
        monday: 1,
        lunes: 1,
        tuesday: 2,
        martes: 2,
        wednesday: 3,
        miercoles: 3,
        thursday: 4,
        jueves: 4,
        friday: 5,
        viernes: 5,
        saturday: 6,
        sabado: 6,
        sunday: 7,
        domingo: 7,
    }
    const relativeWeekday =
        normalized.match(/^(?:el\s+)?([a-z]+)\s+pasado$/) ??
        normalized.match(/^(?:el\s+)?pasado\s+([a-z]+)$/) ??
        normalized.match(/^(?:last|this\s+past)\s+([a-z]+)$/)
    if (relativeWeekday) {
        const targetWeekday = weekdays[relativeWeekday[1]]
        if (targetWeekday !== undefined) {
            const currentWeekday = now.getDay() === 0 ? 7 : now.getDay()
            let daysBack = (currentWeekday - targetWeekday + 7) % 7
            if (daysBack === 0) daysBack = 7
            return day(-daysBack)
        }
    }

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

export type TransactionTimeStatus = 'confirmed' | 'approximation' | 'none'

/**
 * Resolves the timestamp persisted for a transaction under the time-status
 * contract. Exact and approximate times are supplied by the agent. When no
 * time clue exists, preserve the requested calendar day but use the load
 * clock, including seconds and milliseconds.
 */
export function parseTransactionDate(
    input: string | undefined,
    timeStatus: TransactionTimeStatus,
    time?: string,
    now: Date = new Date(),
): bigint {
    const parsed =
        input === undefined ? undefined : parseNaturalDate(input, now)
    if (timeStatus !== 'none') {
        // A confirmed/approximate hour needs a real clock, which can arrive
        // either as the separate `time` argument or embedded in an ISO
        // datetime `input`. What we must reject is having no clock at all:
        // otherwise we persist a bare midnight flagged as a known hour,
        // dropping the part-of-day signal ("tarde", "mañana").
        if (time !== undefined) {
            const match = time.trim().match(/^([01]?\d|2[0-3]):([0-5]\d)$/)
            if (!match) {
                throw new Error(`Invalid transaction time: ${time}`)
            }
            const selectedDate = new Date(
                parsed === undefined ? now.getTime() : Number(parsed),
            )
            const hour = Number(match[1])
            const minute = Number(match[2])
            selectedDate.setHours(hour, minute, 0, 0)
            // A time inside a DST spring-forward gap does not exist locally;
            // setHours silently shifts it forward (e.g. 02:30 → 03:30), so the
            // stored timestamp would disagree with the supplied clock. Reject
            // it instead of persisting a wrong hour under the same timeStatus.
            if (
                selectedDate.getHours() !== hour ||
                selectedDate.getMinutes() !== minute
            ) {
                throw new Error(`Nonexistent local time: ${time}`)
            }
            return BigInt(selectedDate.getTime())
        }
        if (parsed === undefined) {
            throw new Error(
                `date or time is required when timeStatus is ${timeStatus}`,
            )
        }
        // The clock may be embedded in an ISO datetime `input`. Detect it from
        // the input string (a `HH:mm` component), not from zeroed timestamp
        // fields — a real midnight like `2026-08-06T00:00:00` is a valid
        // confirmed time and must not be mistaken for a date-only value.
        const inputHasTime = input !== undefined && /\d{1,2}:\d{2}/.test(input)
        if (!inputHasTime) {
            throw new Error(`time is required when timeStatus is ${timeStatus}`)
        }
        return parsed
    }

    if (parsed === undefined) return BigInt(now.getTime())

    const selectedDate = new Date(Number(parsed))
    selectedDate.setHours(
        now.getHours(),
        now.getMinutes(),
        now.getSeconds(),
        now.getMilliseconds(),
    )
    return BigInt(selectedDate.getTime())
}

/** Case-insensitive name match. Used by entity resolvers. */
export function normalizeName(name: string): string {
    return name.trim().toLocaleLowerCase()
}
