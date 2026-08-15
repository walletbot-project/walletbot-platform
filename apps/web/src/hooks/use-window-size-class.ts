import { useSyncExternalStore } from 'react'

/**
 * Material 3 window size classes. Compact is phone-sized; medium covers small
 * tablets and split-screen; expanded is large tablets and desktop.
 *
 * Mirrors `apps/native/lib/shared/breakpoints.dart` — same names, same
 * thresholds — so both clients switch layouts at the same widths.
 */
export type WindowSizeClass = 'compact' | 'medium' | 'expanded'

/**
 * Width thresholds (px) between the window size classes. `expanded` gates the
 * divided (split) views, so it sits above the Material default (900) to keep
 * the single-column layout until there's comfortable room for two.
 */
export const BREAKPOINTS = {
    medium: 600,
    expanded: 1000,
} as const

function resolve(width: number): WindowSizeClass {
    if (width >= BREAKPOINTS.expanded) return 'expanded'
    if (width >= BREAKPOINTS.medium) return 'medium'
    return 'compact'
}

const mediumQuery = `(min-width: ${BREAKPOINTS.medium}px)`
const expandedQuery = `(min-width: ${BREAKPOINTS.expanded}px)`

function subscribe(onChange: () => void) {
    const queries = [
        window.matchMedia(mediumQuery),
        window.matchMedia(expandedQuery),
    ]
    for (const query of queries) query.addEventListener('change', onChange)
    return () => {
        for (const query of queries)
            query.removeEventListener('change', onChange)
    }
}

function getSnapshot(): WindowSizeClass {
    return resolve(window.innerWidth)
}

/**
 * The current window size class, recomputed when the window crosses a
 * breakpoint.
 */
export function useWindowSizeClass(): WindowSizeClass {
    // Rendered on the client only, so the server snapshot can assume the
    // narrowest layout.
    return useSyncExternalStore(subscribe, getSnapshot, () => 'compact')
}
