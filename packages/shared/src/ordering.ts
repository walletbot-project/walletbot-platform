/**
 * The user-chosen display order of accounts and categories.
 *
 * `position` is written only when the user reorders a list: every active row
 * in that list gets its index. A row without one — created afterwards, or by a
 * client that predates ordering — goes after every positioned row, in creation
 * order, which is exactly where a new item appeared before ordering existed.
 * The native repositories mirror this rule in SQL
 * (`position IS NULL, position, created_at`); keep them in lockstep.
 */
export type Orderable = {
    position?: number
    createdAt: bigint
}

export function compareByPosition(a: Orderable, b: Orderable): number {
    if (a.position !== undefined && b.position !== undefined) {
        if (a.position !== b.position) return a.position - b.position
    } else if (a.position !== undefined) {
        return -1
    } else if (b.position !== undefined) {
        return 1
    }
    if (a.createdAt === b.createdAt) return 0
    return a.createdAt < b.createdAt ? -1 : 1
}

/**
 * The order of tags within one level of the tag tree (siblings sharing a
 * `parentId`). Same rule as {@link compareByPosition}, except that rows
 * without a position fall back to **name** order, which is how tags were
 * always listed: a user who never reorders sees no change, and a new tag
 * lands after the reordered ones, alphabetically among the rest. The native
 * repository mirrors this in SQL
 * (`position IS NULL, position, name COLLATE NOCASE`).
 */
export type NamedOrderable = {
    position?: number
    name: string
}

export function compareByPositionThenName(
    a: NamedOrderable,
    b: NamedOrderable,
): number {
    if (a.position !== undefined && b.position !== undefined) {
        if (a.position !== b.position) return a.position - b.position
    } else if (a.position !== undefined) {
        return -1
    } else if (b.position !== undefined) {
        return 1
    }
    return a.name.localeCompare(b.name, undefined, { sensitivity: 'base' })
}

/** Upper bound on one reorder write: a whole list moves in one mutation. */
export const MAX_REORDER_ITEMS = 500
