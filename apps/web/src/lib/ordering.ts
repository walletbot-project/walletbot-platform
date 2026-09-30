import { compareByPosition, type Orderable } from '@wallet-bot/shared'

/**
 * What a list looks like after a `reorder` mutation with `ids`, for Convex
 * optimistic updates: each listed row takes its index as `position` (exactly
 * what the backend writes) and the list is re-sorted with the backend's own
 * comparator, so the optimistic order and the confirmed one never disagree.
 */
export function applyReorder<T extends Orderable & { id: string }>(
    rows: readonly T[],
    ids: readonly string[],
): T[] {
    const positions = new Map(ids.map((id, index) => [id, index]))
    return rows
        .map((row) => {
            const position = positions.get(row.id)
            return position === undefined ? row : { ...row, position }
        })
        .sort(compareByPosition)
}
