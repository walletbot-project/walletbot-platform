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
 * **The boundary is the end of the current 20-minute block.** It used to be
 * the end of the local day, which meant a movement dated tonight at 20:00
 * counted toward today's balance from the moment the day started. Twenty
 * minutes is fine enough that a movement lands in Activity when it actually
 * happens, and coarse enough to keep the cache below.
 *
 * It rounds **up**, not down, and that is load-bearing: the cutoff is an
 * exclusive upper bound, so rounding down would put a movement recorded *right
 * now* above it and make the expense the user just entered vanish from
 * Activity for up to twenty minutes. Rounding up keeps the old rule's
 * direction — err toward "already happened" — with a finer grain. The cost is
 * that a movement due in the next few minutes counts as done slightly early,
 * which nobody can see.
 *
 * **The cutoff is computed on the client and travels as an argument**, never
 * derived from `Date.now()` inside a Convex query. A Convex query is cached
 * against its arguments and its data dependencies — the passage of time is
 * neither. A query that read the clock itself would keep serving a stale
 * answer to an open subscription long after a movement's date had passed. As
 * an argument, the client decides when the answer is allowed to change, and
 * quantizing is what keeps that from being *every* call: within a block every
 * client sends the same number, so the cached result is reused.
 *
 * Unlike the day boundary it replaces, this one is timezone-independent — the
 * blocks are cut from the epoch, so every client in the world is asking the
 * same question at the same time and shares one cache entry.
 */

/** How coarse the cutoff is. Fine enough to be timely, coarse enough to cache. */
export const OCCURRENCE_BUCKET_MS = 20 * 60 * 1000

/**
 * The end of the 20-minute block `now` falls in, in ms since epoch.
 *
 * Always strictly after `now`, including when `now` sits exactly on a
 * boundary — the same way the old day cutoff was always the *next* midnight.
 */
export function pastCutoffMs(now: Date = new Date()): number {
    const blocks = Math.floor(now.getTime() / OCCURRENCE_BUCKET_MS)
    return (blocks + 1) * OCCURRENCE_BUCKET_MS
}

/** `pastCutoffMs` as the `int64` the Convex transaction queries take. */
export function pastCutoffBigInt(now: Date = new Date()): bigint {
    return BigInt(pastCutoffMs(now))
}
