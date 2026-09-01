/**
 * The boundary between a movement that has already happened and one that has
 * not.
 *
 * A recurring rule materialises its occurrences as ordinary transactions with
 * future dates, so every read that describes "what happened" — the Activity
 * list, an account balance, a category's spend, a dashboard tile — has to stop
 * at this boundary, and the upcoming list has to start at it. The split is
 * invisible to the user: neither side presents it as a filter.
 *
 * **The boundary is the end of the viewer's local day, not the current
 * instant.** A transaction dated today at 20:00 has "happened" from the moment
 * the day starts: it shows in Activity and counts toward the balance all day,
 * which is how the app behaved before recurrence existed. Cutting at the
 * instant instead would make a movement entered this morning for tonight
 * vanish from Activity until 20:00.
 *
 * **The cutoff is computed on the client and travelled as an argument**, never
 * derived from `Date.now()` inside a Convex query. Two reasons, both hard
 * requirements rather than preferences:
 *
 * 1. The server has no idea what day it is *for this user*. "End of today" is
 *    a local-time notion, and a UTC midnight cuts the day in the wrong place
 *    for most of the world.
 * 2. A Convex query is cached against its arguments and its data
 *    dependencies — the passage of time is neither. A query that read the
 *    clock itself would keep serving a stale answer to an open subscription
 *    long after a movement's date had passed. As an argument, the client
 *    decides when the answer is allowed to change.
 */

/** Local-time start of the day after `now`, in ms since epoch. */
export function pastCutoffMs(now: Date = new Date()): number {
    const tomorrow = new Date(
        now.getFullYear(),
        now.getMonth(),
        now.getDate() + 1,
    )
    return tomorrow.getTime()
}

/** `pastCutoffMs` as the `int64` the Convex transaction queries take. */
export function pastCutoffBigInt(now: Date = new Date()): bigint {
    return BigInt(pastCutoffMs(now))
}
