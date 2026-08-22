/**
 * The current calendar month as the half-open window the spend queries take.
 * Computed per render on purpose: the values only change at a month boundary,
 * where a kept-open detail must move to the new month instead of keeping
 * querying the one it mounted in. Convex compares query args by value, so the
 * stable in-month values never resubscribe.
 */
export function currentMonthWindow(): {
    fromMs: bigint
    toExclusiveMs: bigint
} {
    const now = new Date()
    const from = new Date(now.getFullYear(), now.getMonth(), 1)
    const to = new Date(now.getFullYear(), now.getMonth() + 1, 1)
    return {
        fromMs: BigInt(from.getTime()),
        toExclusiveMs: BigInt(to.getTime()),
    }
}
