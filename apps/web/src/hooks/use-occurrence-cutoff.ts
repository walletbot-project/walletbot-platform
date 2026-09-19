import { pastCutoffMs } from '@wallet-bot/shared'
import { useEffect, useState } from 'react'

/**
 * The occurrence cutoff every read that describes "what happened" is bounded
 * by — see `pastCutoffMs` in `@wallet-bot/shared` for why it is the end of the
 * current 20-minute block and why it travels as a query argument.
 *
 * The value is held in state and re-armed for the next boundary, so a tab left
 * open rolls its subscriptions over as movements come due instead of showing a
 * frozen Activity. Because the cutoff is a query argument, moving it is what
 * re-runs the queries — there is nothing else to invalidate, and every client
 * inside a block sends the same number, so they share Convex's cached answer.
 *
 * Not for a `usePaginatedQuery` argument: moving the cutoff there discards the
 * pages instead of refreshing them. Use [usePinnedOccurrenceCutoff].
 */
export function useOccurrenceCutoff(): bigint {
    const [cutoff, setCutoff] = useState(() => pastCutoffMs())

    useEffect(() => {
        // `cutoff` IS the next boundary, so this fires once per block. The
        // second of slack absorbs timer imprecision — waking a hair early
        // would recompute the same cutoff and re-arm in a tight loop. Clamped
        // at 0 in case the boundary passed while the tab was suspended.
        const delay = Math.max(0, cutoff - Date.now())
        const timer = setTimeout(() => setCutoff(pastCutoffMs()), delay + 1000)
        return () => clearTimeout(timer)
    }, [cutoff])

    return BigInt(cutoff)
}

/**
 * The same cutoff for a paginated list: computed once on mount, never re-armed.
 *
 * `usePaginatedQuery` keys its accumulated pages on the serialized arguments,
 * so moving the cutoff does not refresh the list — it throws it away. The hook
 * rebuilds its initial state: back to one page, requested from a null cursor
 * under a fresh id, so not even the page it already held is reused. For a
 * reader scrolled past the first page that means the list collapsing to
 * `initialNumItems`, the scroll position lost, and the sentinel climbing back
 * a page per round trip.
 *
 * The cost of pinning it is that a movement coming due while the screen is
 * open does not cross into the list until the next visit — the same trade the
 * screen already makes for its day headers, which capture `now` once on mount,
 * and no worse than the list before a cutoff existed. Every read that does not
 * paginate keeps [useOccurrenceCutoff], where re-arming costs nothing.
 */
export function usePinnedOccurrenceCutoff(): bigint {
    const [cutoff] = useState(() => pastCutoffMs())
    return BigInt(cutoff)
}
