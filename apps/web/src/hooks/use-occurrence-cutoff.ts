import { pastCutoffMs } from '@wallet-bot/shared'
import { useEffect, useState } from 'react'

/**
 * The occurrence cutoff every read that describes "what happened" is bounded
 * by — see `pastCutoffMs` in `@wallet-bot/shared` for why it is the end of the
 * local day and why it travels as a query argument.
 *
 * The value is held in state and re-armed for the next boundary, so a tab left
 * open across midnight rolls its subscriptions over instead of showing
 * yesterday's Activity forever. Because the cutoff is a query argument, moving
 * it is what re-runs the queries — there is nothing else to invalidate.
 */
export function useOccurrenceCutoff(): bigint {
    const [cutoff, setCutoff] = useState(() => pastCutoffMs())

    useEffect(() => {
        // A `setTimeout` longer than ~24.8 days overflows its 32-bit delay, but
        // the next local midnight is always under a day away, so one timer per
        // boundary is enough. Clamped at 0 in case the boundary already passed
        // while the tab was suspended.
        const delay = Math.max(0, cutoff - Date.now())
        const timer = setTimeout(() => setCutoff(pastCutoffMs()), delay + 1000)
        return () => clearTimeout(timer)
    }, [cutoff])

    return BigInt(cutoff)
}
