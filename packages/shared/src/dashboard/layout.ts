/**
 * The manual dashboard grid engine, ported from
 * apps/native/lib/components/dashboard/dashboard_layout.dart
 * (`DashboardGridLayout`) so both clients compute the same moves, fits, swaps,
 * row inserts and empty-row collapse over the same 6-unit grid.
 *
 * Every mutating operation takes a placement snapshot and returns a new,
 * normalized one — empty rows collapsed, rows renumbered contiguously,
 * placements sorted by row then column — or `null` when the move is invalid, so
 * callers can no-op without persisting.
 */

import {
    collapseEmptyRows,
    type DashboardWidth,
    GRID_UNITS,
    WIDTH_UNITS,
    type WidgetPlacement,
    widthForUnits,
} from './widgets'

/** A directional one-cell move, used by the floating menu's arrow buttons. */
export const MOVE_DIRECTIONS = ['up', 'down', 'left', 'right'] as const
export type MoveDirection = (typeof MOVE_DIRECTIONS)[number]

/** A contiguous half-open run of unoccupied units, `[from, to)`. */
export type UnitRun = { from: number; to: number }

/** Collapses empty rows and sorts by (row, col) — `DashboardGridLayout._normalize`. */
export function normalizeLayout(
    placements: WidgetPlacement[],
): WidgetPlacement[] {
    return collapseEmptyRows(placements).sort(
        (a, b) => a.row - b.row || a.col - b.col,
    )
}

/** One past the last occupied row; 0 for an empty board. */
export function rowCount(placements: WidgetPlacement[]): number {
    return placements.reduce((max, p) => Math.max(max, p.row + 1), 0)
}

export function placementById(
    placements: WidgetPlacement[],
    id: string,
): WidgetPlacement | null {
    return placements.find((p) => p.id === id) ?? null
}

/** The tiles on `row`, left to right. */
export function rowItems(
    placements: WidgetPlacement[],
    row: number,
): WidgetPlacement[] {
    return placements.filter((p) => p.row === row).sort((a, b) => a.col - b.col)
}

/**
 * Per-unit occupancy of `row`. The widget `ignoreId` (the one being moved) is
 * treated as absent so it never blocks its own destination.
 */
export function rowOccupancy(
    placements: WidgetPlacement[],
    row: number,
    ignoreId?: string,
): boolean[] {
    const occupied = new Array<boolean>(GRID_UNITS).fill(false)
    for (const p of placements) {
        if (p.row !== row || p.id === ignoreId) continue
        const end = Math.min(p.col + WIDTH_UNITS[p.width], GRID_UNITS)
        for (let unit = Math.max(p.col, 0); unit < end; unit++) {
            occupied[unit] = true
        }
    }
    return occupied
}

/** The contiguous runs of unoccupied units on `row`. */
export function freeRuns(
    placements: WidgetPlacement[],
    row: number,
    ignoreId?: string,
): UnitRun[] {
    const occupied = rowOccupancy(placements, row, ignoreId)
    const runs: UnitRun[] = []
    let from: number | null = null
    for (let unit = 0; unit <= GRID_UNITS; unit++) {
        const free = unit < GRID_UNITS && !occupied[unit]
        if (free && from === null) from = unit
        if (!free && from !== null) {
            runs.push({ from, to: unit })
            from = null
        }
    }
    return runs
}

/**
 * The widest width that fits starting at (`row`, `col`) — the run of free units
 * from `col` up to the next occupied unit or the grid edge. Null when `col` is
 * out of range or already occupied.
 */
export function fitWidth(
    placements: WidgetPlacement[],
    row: number,
    col: number,
    ignoreId?: string,
): DashboardWidth | null {
    if (col < 0 || col >= GRID_UNITS) return null
    const occupied = rowOccupancy(placements, row, ignoreId)
    if (occupied[col]) return null
    let free = 0
    for (let unit = col; unit < GRID_UNITS && !occupied[unit]; unit++) free++
    return widthForUnits(free)
}

/** Whether `[col, col + units)` on `row` is free of everything but `ignoreIds`. */
function spanFree(
    placements: WidgetPlacement[],
    row: number,
    col: number,
    units: number,
    ignoreIds: ReadonlySet<string>,
): boolean {
    if (row < 0 || col < 0 || col + units > GRID_UNITS) return false
    return !placements.some(
        (p) =>
            !ignoreIds.has(p.id) &&
            p.row === row &&
            col < p.col + WIDTH_UNITS[p.width] &&
            p.col < col + units,
    )
}

function replace(
    placements: WidgetPlacement[],
    next: WidgetPlacement,
): WidgetPlacement[] {
    return normalizeLayout(placements.map((p) => (p.id === next.id ? next : p)))
}

/**
 * Moves `id` to (`row`, `col`) with an optional new `width`. Null when the
 * destination span isn't free. Callers wanting auto-shrink pass the width from
 * [fitWidth].
 */
export function placeAt(
    placements: WidgetPlacement[],
    id: string,
    row: number,
    col: number,
    width?: DashboardWidth,
): WidgetPlacement[] | null {
    const current = placementById(placements, id)
    if (!current) return null
    const next = width ?? current.width
    if (!spanFree(placements, row, col, WIDTH_UNITS[next], new Set([id]))) {
        return null
    }
    return replace(placements, { ...current, row, col, width: next })
}

/**
 * Drops `id` onto the free unit (`row`, `col`), keeping its width unless the
 * free run starting there is narrower — then it shrinks to fit
 * (`_UnitDropTarget`). Null when the unit can't take it.
 */
export function dropOnCell(
    placements: WidgetPlacement[],
    id: string,
    row: number,
    col: number,
): WidgetPlacement[] | null {
    const dragged = placementById(placements, id)
    if (!dragged) return null
    const fit = fitWidth(placements, row, col, id)
    if (fit === null) return null
    const width =
        WIDTH_UNITS[fit] < WIDTH_UNITS[dragged.width] ? fit : dragged.width
    return placeAt(placements, id, row, col, width)
}

/**
 * Inserts a brand-new row at `rowIndex` (shifting rows at/after it down) and
 * drops `id` onto it at `col`. Used by the between-rows drop zones.
 */
export function insertRowAt(
    placements: WidgetPlacement[],
    id: string,
    rowIndex: number,
    col = 0,
): WidgetPlacement[] | null {
    const current = placementById(placements, id)
    if (!current) return null
    if (
        rowIndex < 0 ||
        col < 0 ||
        col + WIDTH_UNITS[current.width] > GRID_UNITS
    )
        return null
    return normalizeLayout(
        placements.map((p) => {
            if (p.id === id) return { ...p, row: rowIndex, col }
            return p.row >= rowIndex ? { ...p, row: p.row + 1 } : p
        }),
    )
}

/**
 * Whether `row` has room to wedge in another tile: at least one `third` (the
 * narrowest width) of free units once `ignoreId` is set aside. Drives the
 * enabled state of the row's vertical insert strips.
 */
export function canInsertInRow(
    placements: WidgetPlacement[],
    row: number,
    ignoreId: string,
): boolean {
    const used = placements
        .filter((p) => p.row === row && p.id !== ignoreId)
        .reduce((sum, p) => sum + WIDTH_UNITS[p.width], 0)
    return GRID_UNITS - used >= WIDTH_UNITS.third
}

/**
 * Wedges `id` into `row` at the ordinal `slot` (0 = before the first tile, N =
 * after the last), shifting the row's other tiles aside and re-flowing them
 * flush left-to-right. The inserted tile auto-shrinks to the free span when it
 * is too wide. Null when the row has no room (see [canInsertInRow]). The tile's
 * old row collapses if it empties.
 */
export function insertInRow(
    placements: WidgetPlacement[],
    id: string,
    row: number,
    slot: number,
): WidgetPlacement[] | null {
    const current = placementById(placements, id)
    if (!current) return null
    const tiles = placements
        .filter((p) => p.row === row && p.id !== id)
        .sort((a, b) => a.col - b.col)
    const usedUnits = tiles.reduce((sum, p) => sum + WIDTH_UNITS[p.width], 0)
    const freeUnits = GRID_UNITS - usedUnits
    if (freeUnits < WIDTH_UNITS.third) return null
    // Shrink only when the tile can't fit the free span as-is.
    const fit = widthForUnits(freeUnits)
    if (fit === null) return null
    const width = WIDTH_UNITS[current.width] <= freeUnits ? current.width : fit

    const ordered = [...tiles]
    ordered.splice(Math.min(Math.max(slot, 0), ordered.length), 0, {
        ...current,
        width,
    })

    const reflowed: WidgetPlacement[] = []
    let col = 0
    for (const p of ordered) {
        reflowed.push({ ...p, row, col })
        col += WIDTH_UNITS[p.width]
    }
    const others = placements.filter((p) => p.row !== row && p.id !== id)
    return normalizeLayout([...others, ...reflowed])
}

/**
 * Swaps the positions of `aId` and `bId` (a tile dropped onto another). Null
 * unless each fits in the other's slot without overlapping a third tile.
 */
export function swapPlacements(
    placements: WidgetPlacement[],
    aId: string,
    bId: string,
): WidgetPlacement[] | null {
    if (aId === bId) return null
    const a = placementById(placements, aId)
    const b = placementById(placements, bId)
    if (!a || !b) return null
    const moving = new Set([aId, bId])
    if (!spanFree(placements, b.row, b.col, WIDTH_UNITS[a.width], moving)) {
        return null
    }
    if (!spanFree(placements, a.row, a.col, WIDTH_UNITS[b.width], moving)) {
        return null
    }
    // The two checks above ignore *both* movers, so they never test the swapped
    // tiles against each other: in the same row, unequal widths can overlap
    // after the swap. Refuse that drop — persisting the overlap would make the
    // resolver discard the whole stored layout to the legacy auto-flow.
    // (Native's `DashboardGridLayout.swap` has this same hole.)
    if (a.row === b.row) {
        const aEnd = b.col + WIDTH_UNITS[a.width]
        const bEnd = a.col + WIDTH_UNITS[b.width]
        if (b.col < bEnd && a.col < aEnd) return null
    }
    return normalizeLayout(
        placements.map((p) => {
            if (p.id === aId) return { ...p, row: b.row, col: b.col }
            if (p.id === bId) return { ...p, row: a.row, col: a.col }
            return p
        }),
    )
}

/**
 * Whether a tile can be nudged down. Moving onto a row that does not exist yet
 * is allowed — it is how a tile boxed in on the bottom row gets out of the way
 * so a neighbour can grow — but only when the tile leaves something behind. A
 * tile *alone* on the last row would vacate that row, the empty-row collapse
 * would renumber the new row straight back to the old index, and nothing would
 * have moved.
 */
function canNudgeDown(
    placements: WidgetPlacement[],
    p: WidgetPlacement,
): boolean {
    if (p.row < rowCount(placements) - 1) return true
    return rowItems(placements, p.row).length > 1
}

/**
 * One-cell nudge. Horizontal moves slide by a single unit into adjacent free
 * space; vertical moves jump to the same column on the neighbouring row when it
 * is free — including a fresh row past the last one (see [canNudgeDown]). Null
 * when blocked or out of bounds, so the matching arrow button can disable.
 */
export function nudgePlacement(
    placements: WidgetPlacement[],
    id: string,
    direction: MoveDirection,
): WidgetPlacement[] | null {
    const p = placementById(placements, id)
    if (!p) return null
    switch (direction) {
        case 'left':
            return placeAt(placements, id, p.row, p.col - 1)
        case 'right':
            return placeAt(placements, id, p.row, p.col + 1)
        case 'up':
            return p.row > 0 ? placeAt(placements, id, p.row - 1, p.col) : null
        case 'down':
            return canNudgeDown(placements, p)
                ? placeAt(placements, id, p.row + 1, p.col)
                : null
    }
}

/** The directions `id` can currently be nudged in. */
export function enabledDirections(
    placements: WidgetPlacement[],
    id: string,
): MoveDirection[] {
    return MOVE_DIRECTIONS.filter(
        (direction) => nudgePlacement(placements, id, direction) !== null,
    )
}

/**
 * Re-fits `id` to `width`, keeping its column when the wider span is free,
 * otherwise sliding left to the nearest free span, and finally clamping the
 * width down to whatever fits at its column. Never overlaps a neighbour; null
 * when nothing can change.
 */
export function resizePlacement(
    placements: WidgetPlacement[],
    id: string,
    width: DashboardWidth,
): WidgetPlacement[] | null {
    const current = placementById(placements, id)
    if (!current) return null
    const units = WIDTH_UNITS[width]
    const ignore = new Set([id])
    // Keep the current column if the new span fits there.
    if (spanFree(placements, current.row, current.col, units, ignore)) {
        return replace(placements, { ...current, width })
    }
    // Otherwise slide left to the nearest column with a free span of `units`.
    for (let col = current.col - 1; col >= 0; col--) {
        if (spanFree(placements, current.row, col, units, ignore)) {
            return replace(placements, { ...current, col, width })
        }
    }
    // Can't grow without overlapping: clamp to the widest width that fits.
    const fit = fitWidth(placements, current.row, current.col, id)
    if (fit === null || fit === current.width) return null
    return replace(placements, { ...current, width: fit })
}
