/**
 * What a list looks like after a `reorder` mutation with `ids`, for Convex
 * optimistic updates: each listed row takes its index as `position` (exactly
 * what the backend writes) and the list is re-sorted with the backend's own
 * comparator (`compareByPosition`, or `compareByPositionThenName` for tags),
 * so the optimistic order and the confirmed one never disagree.
 */
export function applyReorder<T extends { id: string; position?: number }>(
    rows: readonly T[],
    ids: readonly string[],
    compare: (a: T, b: T) => number,
): T[] {
    const positions = new Map(ids.map((id, index) => [id, index]))
    return rows
        .map((row) => {
            const position = positions.get(row.id)
            return position === undefined ? row : { ...row, position }
        })
        .sort(compare)
}
