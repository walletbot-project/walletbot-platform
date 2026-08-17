// Date parsing for the server-side agent.
//
// Why this exists instead of `parseNaturalDate` from `@wallet-bot/shared`:
// that helper resolves "today" using the *host's* local calendar, which is
// correct on a phone and wrong on a server. Convex runs in UTC, so an expense
// a user in Buenos Aires reports at 22:00 would be filed under tomorrow — and
// in a finance app the calendar day is the axis everything is read along.
//
// So the agent carries the user's UTC offset explicitly and every computation
// here is done with `Date.UTC` / `getUTC*` on a shifted instant. Nothing reads
// the ambient timezone, which makes the result identical no matter where the
// action happens to run.
//
// Known limitation: a fixed offset has no DST. For the countries this reaches
// today that is either exact (Argentina, Colombia, Mexico, Peru — no DST) or
// wrong by one hour for part of the year (Chile, Paraguay), and a one-hour
// error only changes the calendar day for messages sent within an hour of
// midnight. Recorded in docs/riesgos.md rather than solved with a timezone
// database.

const MINUTE_MS = 60 * 1000
const DAY_MS = 24 * 60 * MINUTE_MS

export type TransactionTimeStatus = 'confirmed' | 'approximation' | 'none'

// A wall clock in the user's timezone, expressed as UTC fields so every
// helper below can use the `getUTC*` family and never touch local time.
type LocalClock = {
    year: number
    month: number // 0-indexed, matching Date
    day: number
    hour: number
    minute: number
    second: number
    ms: number
}

const toLocalClock = (epochMs: number, offsetMinutes: number): LocalClock => {
    const shifted = new Date(epochMs + offsetMinutes * MINUTE_MS)
    return {
        year: shifted.getUTCFullYear(),
        month: shifted.getUTCMonth(),
        day: shifted.getUTCDate(),
        hour: shifted.getUTCHours(),
        minute: shifted.getUTCMinutes(),
        second: shifted.getUTCSeconds(),
        ms: shifted.getUTCMilliseconds(),
    }
}

// Inverse of `toLocalClock`: a wall clock back to a real instant.
const toEpochMs = (clock: LocalClock, offsetMinutes: number): number =>
    Date.UTC(
        clock.year,
        clock.month,
        clock.day,
        clock.hour,
        clock.minute,
        clock.second,
        clock.ms,
    ) -
    offsetMinutes * MINUTE_MS

// Midnight, in the user's timezone, `dayOffset` days from now.
const midnightAt = (
    nowMs: number,
    offsetMinutes: number,
    dayOffset: number,
): number => {
    const clock = toLocalClock(nowMs + dayOffset * DAY_MS, offsetMinutes)
    return toEpochMs(
        { ...clock, hour: 0, minute: 0, second: 0, ms: 0 },
        offsetMinutes,
    )
}

// ISO weekday of an instant in the user's timezone: 1 = Monday … 7 = Sunday.
const isoWeekday = (epochMs: number, offsetMinutes: number): number => {
    const day = new Date(epochMs + offsetMinutes * MINUTE_MS).getUTCDay()
    return day === 0 ? 7 : day
}

const WEEKDAYS: Record<string, number> = {
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

// Mirrors `parseNaturalDate` in packages/shared/src/tools/parsing.ts — same
// accepted phrases, same fallbacks — but resolved against the user's offset.
// Returns midnight of the resolved calendar day unless the input carried an
// explicit clock.
export const parseAgentDate = (
    input: string,
    nowMs: number,
    offsetMinutes: number,
): number => {
    const trimmed = input.trim().toLowerCase()
    const normalized = trimmed.normalize('NFD').replace(/[\u0300-\u036f]/g, '')

    // A bare calendar date is a *local* day. Parsing it as UTC would shift it
    // backwards for every negative offset, which is all of Latin America.
    const isoDate = normalized.match(/^(\d{4})-(\d{2})-(\d{2})$/)
    if (isoDate) {
        const year = Number(isoDate[1])
        const month = Number(isoDate[2])
        const day = Number(isoDate[3])
        const epoch = toEpochMs(
            {
                year,
                month: month - 1,
                day,
                hour: 0,
                minute: 0,
                second: 0,
                ms: 0,
            },
            offsetMinutes,
        )
        // Rejects impossible days (2026-02-31) that would silently roll over.
        const back = toLocalClock(epoch, offsetMinutes)
        if (
            back.year !== year ||
            back.month !== month - 1 ||
            back.day !== day
        ) {
            throw new Error(`Unrecognized date: ${input}`)
        }
        return epoch
    }

    if (normalized === 'today' || normalized === 'hoy') {
        return midnightAt(nowMs, offsetMinutes, 0)
    }
    if (normalized === 'yesterday' || normalized === 'ayer') {
        return midnightAt(nowMs, offsetMinutes, -1)
    }
    if (normalized === 'anteayer' || normalized === 'day before yesterday') {
        return midnightAt(nowMs, offsetMinutes, -2)
    }
    if (normalized === 'tomorrow' || normalized === 'manana') {
        return midnightAt(nowMs, offsetMinutes, 1)
    }

    const daysAgo =
        normalized.match(/^hace\s+(\d+)\s+dias?$/) ??
        normalized.match(/^(\d+)\s+days?\s+ago$/)
    if (daysAgo) {
        return midnightAt(nowMs, offsetMinutes, -Number(daysAgo[1]))
    }

    const relativeWeekday =
        normalized.match(/^(?:el\s+)?([a-z]+)\s+pasado$/) ??
        normalized.match(/^(?:el\s+)?pasado\s+([a-z]+)$/) ??
        normalized.match(/^(?:last|this\s+past)\s+([a-z]+)$/)
    if (relativeWeekday) {
        const target = WEEKDAYS[relativeWeekday[1]]
        if (target !== undefined) {
            const current = isoWeekday(nowMs, offsetMinutes)
            let daysBack = (current - target + 7) % 7
            if (daysBack === 0) daysBack = 7
            return midnightAt(nowMs, offsetMinutes, -daysBack)
        }
    }

    // An ISO datetime with no zone ("2026-08-17T14:30") is the user's own wall
    // clock. It is parsed field by field rather than handed to `Date.parse`,
    // which resolves that form against the *host* timezone — the exact
    // ambient dependency this module exists to avoid.
    const localDateTime = normalized.match(
        /^(\d{4})-(\d{2})-(\d{2})[t ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.(\d{1,3}))?$/,
    )
    if (localDateTime) {
        return toEpochMs(
            {
                year: Number(localDateTime[1]),
                month: Number(localDateTime[2]) - 1,
                day: Number(localDateTime[3]),
                hour: Number(localDateTime[4]),
                minute: Number(localDateTime[5]),
                second: Number(localDateTime[6] ?? 0),
                ms: Number((localDateTime[7] ?? '0').padEnd(3, '0')),
            },
            offsetMinutes,
        )
    }

    // Anything left carries its own zone (or is not a date at all). A value
    // that states an offset already names an instant, so it is taken as-is.
    const parsed = Date.parse(input)
    if (Number.isNaN(parsed)) {
        throw new Error(`Unrecognized date: ${input}`)
    }
    return parsed
}

// Applies the time-status contract from the tool definitions. Mirrors
// `parseTransactionDate` in the shared package, offset-aware.
//
//  - `confirmed` / `approximation` need a real clock, supplied either as the
//    separate `time` argument or embedded in an ISO datetime. Without one we
//    would persist midnight flagged as a known hour, silently destroying the
//    part-of-day signal ("a la tarde").
//  - `none` keeps the requested calendar day but uses the current clock, so
//    same-day entries stay in the order they were reported.
export const parseAgentTransactionDate = (
    input: string | undefined,
    timeStatus: TransactionTimeStatus,
    time: string | undefined,
    nowMs: number,
    offsetMinutes: number,
): number => {
    const parsed =
        input === undefined || input.trim().length === 0
            ? undefined
            : parseAgentDate(input, nowMs, offsetMinutes)

    if (timeStatus !== 'none') {
        if (time !== undefined && time.trim().length > 0) {
            const match = time.trim().match(/^([01]?\d|2[0-3]):([0-5]\d)$/)
            if (!match) throw new Error(`Invalid transaction time: ${time}`)
            const base = toLocalClock(parsed ?? nowMs, offsetMinutes)
            return toEpochMs(
                {
                    ...base,
                    hour: Number(match[1]),
                    minute: Number(match[2]),
                    second: 0,
                    ms: 0,
                },
                offsetMinutes,
            )
        }
        if (parsed === undefined) {
            throw new Error(
                `date or time is required when timeStatus is ${timeStatus}`,
            )
        }
        // Detected from the string, not from zeroed fields: a real midnight is
        // a legitimate confirmed time.
        if (input === undefined || !/\d{1,2}:\d{2}/.test(input)) {
            throw new Error(`time is required when timeStatus is ${timeStatus}`)
        }
        return parsed
    }

    if (parsed === undefined) return nowMs

    const day = toLocalClock(parsed, offsetMinutes)
    const now = toLocalClock(nowMs, offsetMinutes)
    return toEpochMs(
        {
            ...day,
            hour: now.hour,
            minute: now.minute,
            second: now.second,
            ms: now.ms,
        },
        offsetMinutes,
    )
}

// End of the day `input` falls on, in the user's timezone. Date-range filters
// are inclusive of the whole closing day — "del 1 al 15" must include
// everything spent on the 15th, not just its first millisecond.
export const parseAgentDateEndOfDay = (
    input: string,
    nowMs: number,
    offsetMinutes: number,
): number => {
    const start = parseAgentDate(input, nowMs, offsetMinutes)
    const clock = toLocalClock(start, offsetMinutes)
    return toEpochMs(
        { ...clock, hour: 23, minute: 59, second: 59, ms: 999 },
        offsetMinutes,
    )
}

// `YYYY-MM-DD HH:mm` in the user's timezone. Tool results carry this next to
// the raw epoch so the model can answer "when was that?" without doing
// timezone arithmetic in its head — which it does badly.
export const formatLocalDateTime = (
    epochMs: number,
    offsetMinutes: number,
): string => {
    const d = new Date(epochMs + offsetMinutes * MINUTE_MS)
    const pad = (value: number, size = 2): string =>
        String(value).padStart(size, '0')
    return (
        `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}` +
        ` ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`
    )
}

// Human-readable "today" for the system prompt, in the user's timezone.
export const describeToday = (nowMs: number, offsetMinutes: number): string => {
    const shifted = new Date(nowMs + offsetMinutes * MINUTE_MS)
    const weekday = shifted.toLocaleDateString('en-US', {
        weekday: 'long',
        timeZone: 'UTC',
    })
    const date = shifted.toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric',
        timeZone: 'UTC',
    })
    const hh = String(shifted.getUTCHours()).padStart(2, '0')
    const mm = String(shifted.getUTCMinutes()).padStart(2, '0')
    return `${weekday}, ${date}, ${hh}:${mm} local time`
}
