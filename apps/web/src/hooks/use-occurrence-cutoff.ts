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
