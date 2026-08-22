import type { CSSProperties } from 'react'

/**
 * M3 expressive grouped-list shape tokens, matching
 * `apps/native/lib/components/grouped_card.dart`: a large radius on the outer
 * ends of a group, a minimal one on the seams between adjacent cards, and a
 * hairline gap between them.
 */
export const GROUP_OUTER_RADIUS = 24
export const GROUP_INNER_RADIUS = 4
export const GROUP_SPACING = 2

/**
 * Corner shape for the card at `index` within a group of `count`.
 */
export function groupedRadius(index: number, count: number): CSSProperties {
    const top = index === 0 ? GROUP_OUTER_RADIUS : GROUP_INNER_RADIUS
    const bottom = index === count - 1 ? GROUP_OUTER_RADIUS : GROUP_INNER_RADIUS
    return {
        borderRadius: `${top}px ${top}px ${bottom}px ${bottom}px`,
    }
}
