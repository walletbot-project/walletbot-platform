/**
 * A date and time for the back office. Convex `v.int64()` timestamps arrive as a
 * bigint, the auth component's as a number; both are epoch milliseconds.
 */
export function formatMoment(millis: bigint | number, locale: string): string {
    return new Date(Number(millis)).toLocaleString(locale, {
        dateStyle: 'medium',
        timeStyle: 'short',
    })
}
