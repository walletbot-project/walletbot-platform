// TEMPORARY, for bisecting a reported drag-and-drop failure: opts this module
// out of React Compiler memoization (react.dev § react-compiler/directives/
// use-no-memo — module level, so every function here is left exactly as
// written). Remove once the cause is known; the board is meant to compile.
'use no memo'

import { api } from '@wallet-bot/backend/api'
import {
    canInsertInRow,
    rowCount as countRows,
    type DashboardWidth,
    dropOnCell,
    EMPTY_FILTER,
    enabledDirections,
    filterConfigToJson,
    freeRuns,
    GRID_UNITS,
    insertInRow,
    insertRowAt,
    type LayoutCoord,
    type MoveDirection,
    normalizeLayout,
    nudgePlacement,
    type PlacementInput,
    parseFilterConfig,
    parseWidgetOptions,
    resizePlacement,
    resolvePlacements,
    rowItems,
    swapPlacements,
    WIDTH_UNITS,
    type WidgetPlacement,
    widthForUnits,
    writeLayout,
} from '@wallet-bot/shared'
import { IconButton } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { Icon } from '@/components/m3/icon'
import { Skeleton } from '@/components/ui/skeleton'
import { useElementWidth } from '@/hooks/use-element-width'
import { dashboardTitle, useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'
import { defaultDashboardSeed } from '@/pages/home/default-dashboard'
import { widgetLabel, widthLabel } from '@/pages/home/labels'
import {
    type DropTarget,
    type TileDrag,
    useLongPress,
    useTileDrag,
} from '@/pages/home/use-tile-drag'
import {
    BalanceCardWidget,
    BreakdownChartWidget,
    StatWidget,
    TransactionListWidget,
    type WidgetSpec,
} from '@/pages/home/widgets'

/**
 * Grid metrics, ported from `DashboardView`
 * (apps/native/lib/components/dashboard/dashboard_view.dart): the gap between
 * tiles inside one logical row, the gap between logical rows placed side by
 * side, the width a logical row needs before another can sit beside it, and the
 * cap on how many ever do.
 */
const TILE_GAP = 4
const BAND_GAP = 16
const MIN_LOGICAL_ROW_WIDTH = 380
const MAX_BAND_COLUMNS = 3

/**
 * Hit width of the between-tile insert strips and hit height of the new-row
 * drop bands (`_insertHit` / `_rowBand`). Both live in an overlay, so their
 * generous hit areas never change the row's own size — toggling edit mode
 * shifts nothing.
 */
const INSERT_HIT = 22
const ROW_BAND = 16

/** One grid unit as a CSS length, given the row is `GRID_UNITS` equal columns. */
const UNIT = `((100% - ${TILE_GAP * (GRID_UNITS - 1)}px) / ${GRID_UNITS})`

/** The x of column `col`'s left edge, matching native's `columnLeft`. */
function columnLeft(col: number): string {
    return `calc(${col} * (${UNIT} + ${TILE_GAP}px))`
}

type LayoutRow = {
    id: string
    type: string
    filterId: string | null
    position: number
    width: string
    options: string
}

export type DashboardWidgetRow = LayoutRow

type SpecEntry = { row: LayoutRow; spec: WidgetSpec }

/**
 * The home dashboard: the manual 6-unit grid of configured widgets, ported
 * from the native `DashboardSection` (docs/home-dashboard.md § "Layout: manual
 * grid").
 *
 * Editing offers the same affordances as the native board: drag a tile onto a
 * free cell (auto-shrinking to the run), onto another tile to swap, onto the
 * seam between two tiles to wedge it into that row, or onto a row's edge band
 * to open a fresh row there; plus the floating menu's width controls, one-cell
 * nudges, edit and delete, and a `+` in every empty run to add a widget right
 * there. All of it runs through the shared layout engine in
 * `@wallet-bot/shared`, so both clients resolve, move and repair a stored
 * layout identically.
 */
export function Dashboard({
    editing,
    onStartEditing,
    onEditWidget,
    onAddWidgetAt,
}: {
    editing: boolean
    onStartEditing: () => void
    onEditWidget: (widget: LayoutRow) => void
    /** Opens the add flow targeting one empty cell, capped to its free run. */
    onAddWidgetAt: (coord: LayoutCoord, maxUnits: number) => void
}) {
    const t = useT()
    const navigate = useNavigate()
    const layout = useQuery(api.v1.dashboard.queries.layout)
    const seed = useMutation(api.v1.dashboard.mutations.seedDefaultIfEmpty)
    // Optimistic: a dragged tile lands under the pointer immediately instead of
    // snapping back until the round-trip returns, which is what makes the
    // native board feel direct. Convex rolls the patch back by itself if the
    // mutation fails, and `persist` surfaces the failure as a toast.
    const saveLayout = useMutation(
        api.v1.dashboard.mutations.saveLayout,
    ).withOptimisticUpdate((localStore, args) => {
        const current = localStore.getQuery(api.v1.dashboard.queries.layout, {})
        if (!current) return
        const byId = new Map(args.widgets.map((entry) => [entry.id, entry]))
        const widgets = current.widgets
            .map((widget) => {
                const next = byId.get(widget.id)
                return next
                    ? {
                          ...widget,
                          position: next.position,
                          width: next.width,
                          options: next.options,
                      }
                    : widget
            })
            .sort((a, b) => a.position - b.position)
        localStore.setQuery(
            api.v1.dashboard.queries.layout,
            {},
            { ...current, widgets },
        )
    })
    const archiveWidget = useMutation(
        api.v1.dashboard.mutations.archiveWidget,
    ).withOptimisticUpdate((localStore, args) => {
        const current = localStore.getQuery(api.v1.dashboard.queries.layout, {})
        if (!current) return
        localStore.setQuery(
            api.v1.dashboard.queries.layout,
            {},
            {
                ...current,
                widgets: current.widgets.filter(
                    (widget) => widget.id !== args.id,
                ),
            },
        )
    })
    const seededRef = useRef(false)
    const [measureRef, width] = useElementWidth()
    // Only the selected tile shows its floating menu. Derived rather than
    // cleared in an effect, which is also exactly how native reads it:
    // `selected = editing && selectedItemId == item.row.id`.
    const [pickedId, setSelectedId] = useState<string | null>(null)
    const selectedId = editing ? pickedId : null
    const [pendingDelete, setPendingDelete] = useState<LayoutRow | null>(null)

    // Seed once per session, and only for an account that has never had a
    // dashboard — the mutation itself re-checks and refuses to resurrect one
    // the user deliberately emptied.
    useEffect(() => {
        if (layout === undefined || seededRef.current) return
        if (layout.widgets.length > 0 || layout.filters.length > 0) return
        seededRef.current = true
        void seed(defaultDashboardSeed(t)).catch(() => {
            // A failed seed leaves an empty dashboard the user can populate by
            // hand; nothing else in the screen depends on it.
            seededRef.current = false
        })
    }, [layout, seed, t])

    const filtersById = useMemo(
        () => new Map((layout?.filters ?? []).map((f) => [f.id, f])),
        [layout],
    )

    const specs = useMemo<SpecEntry[]>(() => {
        const rows = layout?.widgets ?? []
        return rows.map((row) => {
            const options = parseWidgetOptions(row.options)
            const saved = row.filterId
                ? filtersById.get(row.filterId)
                : undefined
            const parsed = parseFilterConfig(saved?.config ?? '')
            return {
                row,
                spec: {
                    id: row.id,
                    type: row.type,
                    options,
                    config: saved?.config ?? '',
                    currency: parsed.currency,
                } satisfies WidgetSpec,
            }
        })
    }, [layout, filtersById])

    const resolution = useMemo(() => {
        const inputs: PlacementInput[] = specs.map(({ row, spec }) => ({
            id: row.id,
            width: normalizeWidth(row.width),
            coord: spec.options.layout,
        }))
        const resolved = resolvePlacements(inputs)
        // Normalized on read, the way native wraps the resolver in a
        // `DashboardGridLayout`: a stored snapshot with a hole in its row
        // numbering must not render a band of empty rows.
        return {
            placements: normalizeLayout(resolved.placements),
            needsRepair: resolved.needsRepair,
        }
    }, [specs])
    const placements = resolution.placements

    const persist = useCallback(
        async (next: WidgetPlacement[]) => {
            const ordered = normalizeLayout(next)
            const byId = new Map(specs.map(({ row }) => [row.id, row]))
            const payload = ordered.flatMap((placement, index) => {
                const row = byId.get(placement.id)
                if (!row) return []
                return [
                    {
                        id: placement.id,
                        position: index,
                        width: placement.width,
                        options: writeLayout(row.options, {
                            row: placement.row,
                            col: placement.col,
                        }),
                    },
                ]
            })
            try {
                await saveLayout({ widgets: payload })
            } catch {
                toast.error(t.dashboard.layoutSaveFailed)
            }
        },
        [specs, saveLayout, t],
    )

    const { drag, startTracking, wasDragged } = useTileDrag(
        useCallback(
            (draggedId: string, target: DropTarget) => {
                const next = applyDrop(placements, draggedId, target)
                // A drop the layout can't take is simply refused, the way the
                // native drag targets reject it before it lands.
                if (next) void persist(next)
            },
            [placements, persist],
        ),
    )

    if (layout === undefined) return <DashboardSkeleton />

    if (specs.length === 0) {
        return (
            <button
                type="button"
                onClick={onStartEditing}
                className="m3-state-layer flex w-full cursor-pointer flex-col items-center gap-2 rounded-lg border border-outline-variant border-dashed p-8 text-center"
            >
                <Icon name="dashboard" className="text-on-surface-variant" />
                <span className="m3-title-small text-on-surface">
                    {t.dashboard.emptyTitle}
                </span>
                <span className="m3-body-small text-on-surface-variant">
                    {t.dashboard.emptyDescription}
                </span>
            </button>
        )
    }

    const rowCount = countRows(placements)
    const specById = new Map(specs.map((entry) => [entry.spec.id, entry]))

    /**
     * Opens the add flow at one empty cell. A board whose coordinates were
     * never stored resolves through the legacy auto-flow, so it is written out
     * first — otherwise the new tile's placement would be re-derived and land
     * somewhere else (`_addWidgetAt`).
     */
    const addAt = async (row: number, col: number, maxUnits: number) => {
        if (resolution.needsRepair) await persist(placements)
        onAddWidgetAt({ row, col }, maxUnits)
    }

    const openActivity = (spec: WidgetSpec) => {
        // Tapping a tile outside edit mode opens the activity list scoped to
        // what the tile counts — `_activityFilterFor`. A balance card has no
        // filter of its own, only its currency.
        const config =
            spec.type === 'balance'
                ? filterConfigToJson({
                      ...EMPTY_FILTER,
                      currency: spec.options.currency || null,
                  })
                : spec.config
        navigate('/activity', { state: { filterConfig: config } })
    }

    const renderRow = (rowIndex: number) => {
        const tiles = rowItems(placements, rowIndex)
        const dragging = drag !== null
        const canWedge =
            dragging && canInsertInRow(placements, rowIndex, drag.id)

        return (
            <div
                className="relative grid"
                style={{
                    gridTemplateColumns: `repeat(${GRID_UNITS}, minmax(0, 1fr))`,
                    gap: TILE_GAP,
                }}
            >
                {/*
                 * Every contiguous run of empty units, as one dashed
                 * placeholder with a `+` that adds a widget right there
                 * (`_GapVisual`), over per-unit drop targets so a dropped tile
                 * lands on the exact unit under the pointer and shrinks to the
                 * run (`_UnitDropTarget`). Outside edit mode the run is just
                 * reserved space keeping the tiles aligned.
                 */}
                {editing
                    ? freeRuns(placements, rowIndex).map((run) => (
                          <GapRun
                              key={`gap-${rowIndex}-${run.from}`}
                              row={rowIndex}
                              from={run.from}
                              to={run.to}
                              drag={drag}
                              onAdd={addAt}
                          />
                      ))
                    : null}

                {tiles.map((placement) => {
                    const entry = specById.get(placement.id)
                    if (!entry) return null
                    return (
                        <Tile
                            key={placement.id}
                            placement={placement}
                            placements={placements}
                            entry={entry}
                            editing={editing}
                            selected={placement.id === selectedId}
                            dragging={drag?.id === placement.id}
                            menuHidden={drag !== null}
                            isDropTarget={
                                drag?.over?.kind === 'tile' &&
                                drag.over.id === placement.id
                            }
                            onPointerDownDrag={startTracking}
                            wasDragged={wasDragged}
                            onSelect={() => setSelectedId(placement.id)}
                            onStartEditing={() => {
                                setSelectedId(placement.id)
                                onStartEditing()
                            }}
                            onOpen={() => openActivity(entry.spec)}
                            onEdit={() => onEditWidget(entry.row)}
                            onDelete={() => setPendingDelete(entry.row)}
                            onChange={persist}
                        />
                    )
                })}

                {/*
                 * Drop affordances, overlaid above the tiles so their hit areas
                 * never widen the row. Invisible until a tile is in the air,
                 * and inert (`pointer-events: none`) until then, so the `+`
                 * beneath and the tiles themselves stay clickable — the same
                 * thing native's rejecting `DragTarget`s do.
                 */}
                {editing ? (
                    <>
                        {insertSeams(tiles).map((seam) => (
                            <RowInsertZone
                                key={`seam-${rowIndex}-${seam.slot}`}
                                center={seam.center}
                                active={canWedge}
                                hovered={
                                    drag?.over?.kind === 'row-insert' &&
                                    drag.over.row === rowIndex &&
                                    drag.over.slot === seam.slot
                                }
                                row={rowIndex}
                                slot={seam.slot}
                            />
                        ))}
                        <NewRowZone
                            edge="top"
                            rowIndex={rowIndex}
                            active={dragging}
                            hovered={
                                drag?.over?.kind === 'new-row' &&
                                drag.over.rowIndex === rowIndex
                            }
                        />
                        {rowIndex === rowCount - 1 ? (
                            <NewRowZone
                                edge="bottom"
                                rowIndex={rowIndex + 1}
                                active={dragging}
                                hovered={
                                    drag?.over?.kind === 'new-row' &&
                                    drag.over.rowIndex === rowIndex + 1
                                }
                            />
                        ) : null}
                    </>
                ) : null}
            </div>
        )
    }

    // Reflow, don't stretch. Stored coordinates always stay in 6-unit terms;
    // a wide window only changes how many logical rows sit side by side per
    // visual band — the `DashboardView` `LayoutBuilder` rule.
    const bandColumns =
        width === null
            ? 1
            : Math.min(
                  MAX_BAND_COLUMNS,
                  Math.max(
                      1,
                      Math.floor(
                          (width + BAND_GAP) /
                              (MIN_LOGICAL_ROW_WIDTH + BAND_GAP),
                      ),
                  ),
              )

    // ONE tree for every band count. With `bandColumns === 1` the band grid
    // degenerates to one row per band, which renders identically — a second
    // early-return here would change the tree shape at the width threshold and
    // remount every widget (the exact bug the root layout once had).
    const bandCount = Math.ceil(rowCount / bandColumns)
    return (
        <div
            ref={measureRef}
            className="flex flex-col"
            style={{ gap: TILE_GAP }}
        >
            {Array.from({ length: bandCount }, (_, band) => (
                <div
                    key={band}
                    className="grid items-start"
                    style={{
                        gridTemplateColumns: `repeat(${bandColumns}, minmax(0, 1fr))`,
                        gap: BAND_GAP,
                    }}
                >
                    {Array.from({ length: bandColumns }, (_, column) => {
                        const rowIndex = band * bandColumns + column
                        return (
                            <div key={column} className="min-w-0">
                                {rowIndex < rowCount
                                    ? renderRow(rowIndex)
                                    : null}
                            </div>
                        )
                    })}
                </div>
            ))}

            {drag === null ? null : (
                <DragPreview
                    drag={drag}
                    spec={specById.get(drag.id)?.spec ?? null}
                />
            )}

            <M3Dialog
                open={pendingDelete !== null}
                onOpenChange={(open) => {
                    if (!open) setPendingDelete(null)
                }}
                title={t.dashboard.removeWidget}
                description={
                    pendingDelete
                        ? t.dashboard.removeWidgetConfirmation({
                              title: widgetLabel(
                                  parseWidgetOptions(pendingDelete.options)
                                      .title,
                                  pendingDelete.type,
                                  t,
                              ),
                          })
                        : undefined
                }
                actions={
                    <>
                        <DialogAction
                            label={t.common.cancel}
                            onPress={() => setPendingDelete(null)}
                        />
                        <DialogAction
                            label={t.common.delete}
                            destructive
                            onPress={() => {
                                const target = pendingDelete
                                setPendingDelete(null)
                                if (!target) return
                                if (selectedId === target.id) {
                                    setSelectedId(null)
                                }
                                void archiveWidget({ id: target.id }).catch(
                                    () => toast.error(t.dashboard.deleteFailed),
                                )
                            }}
                        />
                    </>
                }
            />
        </div>
    )
}

/**
 * Applies a completed drop, dispatching to the shared engine op the native
 * board's matching drag target would have run.
 */
function applyDrop(
    placements: WidgetPlacement[],
    draggedId: string,
    target: DropTarget,
): WidgetPlacement[] | null {
    switch (target.kind) {
        case 'tile':
            return swapPlacements(placements, draggedId, target.id)
        case 'cell':
            return dropOnCell(placements, draggedId, target.row, target.col)
        case 'row-insert':
            return insertInRow(placements, draggedId, target.row, target.slot)
        case 'new-row':
            return insertRowAt(placements, draggedId, target.rowIndex)
    }
}

type Seam = { slot: number; center: string }

/**
 * The seams a tile can be wedged into on this row: before a first tile that
 * starts flush left, between two adjacent tiles, and after a last tile that
 * ends flush right. A seam next to a gap is left out — the gap's own unit
 * targets already cover it. Ported from `_buildRow`'s strip placement.
 */
function insertSeams(tiles: WidgetPlacement[]): Seam[] {
    const seams: Seam[] = []
    tiles.forEach((placement, index) => {
        if (index === 0 && placement.col === 0) {
            seams.push({ slot: 0, center: '0px' })
        }
        const previous = tiles[index - 1]
        if (
            previous &&
            previous.col + WIDTH_UNITS[previous.width] === placement.col
        ) {
            seams.push({
                slot: index,
                center: `calc(${columnLeft(placement.col)} - ${TILE_GAP / 2}px)`,
            })
        }
        if (
            index === tiles.length - 1 &&
            placement.col + WIDTH_UNITS[placement.width] === GRID_UNITS
        ) {
            seams.push({ slot: tiles.length, center: '100%' })
        }
    })
    return seams
}

/**
 * One contiguous run of empty units: a dashed placeholder with a `+` when the
 * run is wide enough to hold a widget, plus one drop target per unit layered
 * over it.
 */
function GapRun({
    row,
    from,
    to,
    drag,
    onAdd,
}: {
    row: number
    from: number
    to: number
    drag: TileDrag | null
    onAdd: (row: number, col: number, maxUnits: number) => void
}) {
    const t = useT()
    const span = to - from
    // A run can only hold a widget when it is at least a `1/3` (2 units) wide;
    // narrower runs still show the dashed cell but can't be added or dropped
    // into.
    const canHold = widthForUnits(span) !== null

    return (
        <div
            className="relative rounded-lg border border-outline-variant border-dashed"
            style={{
                gridRow: 1,
                gridColumn: `${from + 1} / span ${span}`,
            }}
        >
            {canHold ? (
                <button
                    type="button"
                    aria-label={t.dashboard.addWidgetHere}
                    onClick={() => onAdd(row, from, span)}
                    className="m3-state-layer absolute inset-0 flex cursor-pointer items-center justify-center rounded-lg text-on-surface-variant/60"
                >
                    <Icon name="add" size={18} />
                </button>
            ) : null}
            <div
                className={cn(
                    'absolute inset-0 grid',
                    drag === null ? 'pointer-events-none' : null,
                )}
                style={{
                    gridTemplateColumns: `repeat(${span}, minmax(0, 1fr))`,
                    gap: TILE_GAP,
                }}
            >
                {Array.from({ length: span }, (_, offset) => {
                    const col = from + offset
                    return (
                        <div
                            key={col}
                            data-drop-kind="cell"
                            data-drop-row={row}
                            data-drop-col={col}
                            className={cn(
                                'm-0.5 rounded-lg',
                                drag?.over?.kind === 'cell' &&
                                    drag.over.row === row &&
                                    drag.over.col === col &&
                                    'bg-primary/16',
                            )}
                        />
                    )
                })}
            </div>
        </div>
    )
}

/**
 * The vertical drop strip at one seam, porting `_RowInsertZone`: dropping here
 * wedges the dragged tile into the row at that position and shifts the others
 * aside. Invisible until a tile is dragged over it, then a full-height bar
 * previews where it will land.
 */
function RowInsertZone({
    center,
    active,
    hovered,
    row,
    slot,
}: {
    center: string
    active: boolean
    hovered: boolean
    row: number
    slot: number
}) {
    return (
        <div
            // A row with no space left rejects the wedge, and an inert strip
            // lets the drop fall through to the tile beneath, exactly as the
            // native `DragTarget` does when `onWillAccept` says no.
            data-drop-kind={active ? 'row-insert' : undefined}
            data-drop-row={row}
            data-drop-slot={slot}
            className={cn(
                'absolute top-0 bottom-0 z-10 flex items-stretch justify-center',
                active ? null : 'pointer-events-none',
            )}
            style={{
                left: `calc(${center} - ${INSERT_HIT / 2}px)`,
                width: INSERT_HIT,
            }}
        >
            <div
                className="rounded-sm bg-primary transition-[width] duration-120"
                style={{ width: hovered ? 4 : 0 }}
            />
        </div>
    )
}

/**
 * A new-row drop band at a row's top or bottom edge, porting
 * `_NewRowDropZone`: dropping here opens a fresh row at that boundary.
 * Overlaid at the edge so the between-row spacing is identical in and out of
 * edit mode.
 */
function NewRowZone({
    edge,
    rowIndex,
    active,
    hovered,
}: {
    edge: 'top' | 'bottom'
    rowIndex: number
    active: boolean
    hovered: boolean
}) {
    return (
        <div
            data-drop-kind={active ? 'new-row' : undefined}
            data-drop-row-index={rowIndex}
            className={cn(
                'absolute right-0 left-0 z-20 flex',
                edge === 'top' ? 'top-0 items-start' : 'bottom-0 items-end',
                active ? null : 'pointer-events-none',
            )}
            style={{ height: ROW_BAND }}
        >
            {hovered ? (
                <div className="h-1 w-full rounded-sm bg-primary" />
            ) : null}
        </div>
    )
}

/**
 * One placed widget. Outside edit mode the whole tile opens the activity list
 * scoped to what it counts, and a press-and-hold arms the editor with this tile
 * selected — the native `InkWell(onTap:, onLongPress:)`. Inside edit mode the
 * tile is a selection target and a drag handle instead of a live widget.
 */
function Tile({
    placement,
    placements,
    entry,
    editing,
    selected,
    dragging,
    menuHidden,
    isDropTarget,
    onPointerDownDrag,
    wasDragged,
    onSelect,
    onStartEditing,
    onOpen,
    onEdit,
    onDelete,
    onChange,
}: {
    placement: WidgetPlacement
    placements: WidgetPlacement[]
    entry: SpecEntry
    editing: boolean
    selected: boolean
    dragging: boolean
    menuHidden: boolean
    isDropTarget: boolean
    onPointerDownDrag: (
        event: React.PointerEvent<HTMLElement>,
        id: string,
    ) => void
    wasDragged: () => boolean
    onSelect: () => void
    onStartEditing: () => void
    onOpen: () => void
    onEdit: () => void
    onDelete: () => void
    onChange: (next: WidgetPlacement[]) => Promise<void>
}) {
    const t = useT()
    const { handlers, wasLongPressed } = useLongPress(onStartEditing)
    const label =
        dashboardTitle(entry.spec.options.title, t) || t.dashboard.widget

    return (
        <div
            key={placement.id}
            data-drop-kind={editing ? 'tile' : undefined}
            data-drop-id={editing ? placement.id : undefined}
            className={cn(
                'relative min-w-0 rounded-lg transition-shadow',
                dragging && 'opacity-35',
                !editing && 'cursor-pointer',
            )}
            style={{
                gridRow: 1,
                gridColumn: `${placement.col + 1} / span ${WIDTH_UNITS[placement.width]}`,
                // The glow the native tile drag target paints while another
                // tile hovers over it.
                boxShadow: isDropTarget
                    ? '0 0 16px 2px color-mix(in srgb, var(--md-sys-color-primary) 22%, transparent)'
                    : undefined,
            }}
            {...(editing
                ? {}
                : {
                      role: 'button',
                      tabIndex: 0,
                      'aria-label': label,
                      // Handlers on the container, not an overlay: a chart's
                      // own tooltips have to keep working underneath.
                      ...handlers,
                      onClick: () => {
                          if (wasLongPressed()) return
                          onOpen()
                      },
                      onKeyDown: (event: React.KeyboardEvent) => {
                          if (event.key !== 'Enter' && event.key !== ' ') return
                          event.preventDefault()
                          onOpen()
                      },
                  })}
        >
            <WidgetBody spec={entry.spec} />
            {editing ? (
                <>
                    {/*
                     * In edit mode the tile is a selection target and a drag
                     * handle, not a live widget — the same thing the native
                     * `InkWell(onTap: onTapItem)` inside
                     * `_MouseFriendlyDraggable` does over the content. The grab
                     * cursor is the only hint a mouse gets that the board
                     * rearranges by dragging.
                     */}
                    <button
                        type="button"
                        aria-pressed={selected}
                        aria-label={label}
                        onPointerDown={(event) =>
                            onPointerDownDrag(event, placement.id)
                        }
                        onClick={() => {
                            // The click that closes a drag is not a selection.
                            if (wasDragged()) return
                            onSelect()
                        }}
                        className={cn(
                            'absolute inset-0 cursor-grab rounded-lg border-2',
                            selected ? 'border-primary' : 'border-transparent',
                        )}
                    />
                    {selected && !menuHidden ? (
                        <TileMenu
                            placement={placement}
                            placements={placements}
                            onEdit={onEdit}
                            onDelete={onDelete}
                            onChange={onChange}
                        />
                    ) : null}
                </>
            ) : null}
        </div>
    )
}

/**
 * The tile that follows the pointer, porting `_DashboardDragPreview`: not the
 * live widget but a card naming it, so a drag costs nothing to render and the
 * board underneath stays the thing being read. Anchored at the pointer, the way
 * `pointerDragAnchorStrategy` anchors the native feedback.
 */
function DragPreview({
    drag,
    spec,
}: {
    drag: TileDrag
    spec: WidgetSpec | null
}) {
    const t = useT()
    if (!spec) return null
    return (
        <div
            className="pointer-events-none fixed z-50 rounded-lg border-2 border-primary bg-surface shadow-level-4"
            style={{
                left: drag.x,
                top: drag.y,
                // The same clamp the native feedback uses, so a `1/3` tile is
                // still readable and a `1/1` one never overflows the viewport.
                width: Math.max(
                    120,
                    Math.min(drag.width, window.innerWidth - 32),
                ),
            }}
        >
            <div className="flex min-h-32 items-center gap-2.5 rounded-md bg-primary/6 p-4">
                <Icon
                    name={previewIcon(spec.type)}
                    className="shrink-0 text-primary"
                />
                <span className="m3-title-small min-w-0 flex-1 truncate font-extrabold text-on-surface">
                    {dashboardTitle(spec.options.title, t) ||
                        t.dashboard.widget}
                </span>
            </div>
        </div>
    )
}

function previewIcon(type: string): string {
    switch (type) {
        case 'list':
            return 'receipt_long'
        case 'balance':
            return 'account_balance_wallet'
        case 'chart':
            return 'donut_large'
        default:
            return 'calculate'
    }
}

function normalizeWidth(width: string): DashboardWidth {
    switch (width) {
        case 'full':
        case 'two_thirds':
        case 'half':
        case 'third':
            return width
        default:
            return 'third'
    }
}

function WidgetBody({ spec }: { spec: WidgetSpec }) {
    switch (spec.type) {
        case 'stat':
            return <StatWidget spec={spec} />
        case 'balance':
            return <BalanceCardWidget spec={spec} />
        case 'list':
            return <TransactionListWidget spec={spec} />
        case 'chart':
            return <BreakdownChartWidget spec={spec} />
        default:
            // Forward-compatible: a type written by a newer client is skipped
            // rather than crashing the dashboard.
            return null
    }
}

/** Width options in the order the native menu lists them. */
const WIDTH_OPTIONS: DashboardWidth[] = ['full', 'two_thirds', 'half', 'third']

const MOVE_ACTIONS: { direction: MoveDirection; icon: string }[] = [
    { direction: 'left', icon: 'arrow_back' },
    { direction: 'up', icon: 'arrow_upward' },
    { direction: 'down', icon: 'arrow_downward' },
    { direction: 'right', icon: 'arrow_forward' },
]

/**
 * The per-tile edit menu, porting `_DashboardFloatingMenu`: a row of `1/1 ·
 * 2/3 · 1/2 · 1/3` width chips followed by edit and delete, over a row of
 * one-cell nudges. Widths run through the engine's `resize`, so growing a tile
 * slides it left or clamps it to the free span instead of doing nothing; a
 * nudge with nowhere to go is disabled.
 */
function TileMenu({
    placement,
    placements,
    onEdit,
    onDelete,
    onChange,
}: {
    placement: WidgetPlacement
    placements: WidgetPlacement[]
    onEdit: () => void
    onDelete: () => void
    onChange: (next: WidgetPlacement[]) => Promise<void>
}) {
    const t = useT()
    const allowed = new Set(enabledDirections(placements, placement.id))

    // The menu hangs just below the tile and anchors to whichever edge points
    // at the screen centre, so it grows inward instead of off the side —
    // `_FloatingMenuAnchor` + `_alignMenuRight`.
    const alignRight =
        placement.col + WIDTH_UNITS[placement.width] / 2 > GRID_UNITS / 2

    return (
        <div
            className={cn(
                'absolute top-full z-30 pt-1.5',
                alignRight ? 'right-0' : 'left-0',
            )}
        >
            <div className="flex w-max flex-col items-center gap-0.5 rounded-lg bg-surface/96 px-1.5 py-1 shadow-level-4">
                <div className="flex items-center gap-1">
                    {WIDTH_OPTIONS.map((option) => {
                        const next = resizePlacement(
                            placements,
                            placement.id,
                            option,
                        )
                        return (
                            <WidthChip
                                key={option}
                                label={widthLabel(option, t)}
                                selected={option === placement.width}
                                isDisabled={next === null}
                                onClick={() => {
                                    if (next) void onChange(next)
                                }}
                            />
                        )
                    })}
                    <TileAction
                        icon="tune"
                        label={t.common.edit}
                        onPress={onEdit}
                    />
                    <TileAction
                        icon="delete"
                        label={t.common.delete}
                        onPress={onDelete}
                        destructive
                    />
                </div>
                <div className="flex items-center">
                    {MOVE_ACTIONS.map(({ direction, icon }) => (
                        <TileAction
                            key={direction}
                            icon={icon}
                            label={moveLabel(direction, t)}
                            isDisabled={!allowed.has(direction)}
                            onPress={() => {
                                const next = nudgePlacement(
                                    placements,
                                    placement.id,
                                    direction,
                                )
                                if (next) void onChange(next)
                            }}
                        />
                    ))}
                </div>
            </div>
        </div>
    )
}

function moveLabel(
    direction: MoveDirection,
    t: ReturnType<typeof useT>,
): string {
    switch (direction) {
        case 'left':
            return t.dashboard.moveLeft
        case 'right':
            return t.dashboard.moveRight
        case 'up':
            return t.dashboard.moveUp
        case 'down':
            return t.dashboard.moveDown
    }
}

/** A 34×30 width chip, filled with `primary` while it is the tile's width. */
function WidthChip({
    label,
    selected,
    isDisabled,
    onClick,
}: {
    label: string
    selected: boolean
    isDisabled: boolean
    onClick: () => void
}) {
    const t = useT()
    return (
        <button
            type="button"
            onClick={onClick}
            disabled={isDisabled}
            aria-pressed={selected}
            aria-label={`${t.dashboard.width} ${label}`}
            className={cn(
                'm3-label-small flex h-7.5 w-8.5 shrink-0 cursor-pointer items-center justify-center rounded-md font-extrabold transition-colors disabled:cursor-not-allowed disabled:opacity-38',
                selected
                    ? 'bg-primary text-on-primary'
                    : 'bg-surface-container-highest text-on-surface-variant',
            )}
        >
            {label}
        </button>
    )
}

function TileAction({
    icon,
    label,
    onPress,
    isDisabled = false,
    destructive = false,
}: {
    icon: string
    label: string
    onPress: () => void
    isDisabled?: boolean
    destructive?: boolean
}) {
    return (
        <IconButton
            aria-label={label}
            onPress={onPress}
            isDisabled={isDisabled}
            // Actify leaves the disabled look to the caller, so dim it here —
            // otherwise an unavailable nudge is indistinguishable from a live
            // one.
            className={cn(
                destructive ? 'text-error' : 'text-on-surface-variant',
                isDisabled && 'opacity-38',
            )}
        >
            <Icon name={icon} size={20} />
        </IconButton>
    )
}

function DashboardSkeleton() {
    return (
        <div className="flex flex-col gap-2">
            <Skeleton className="h-32 w-full rounded-lg" />
            <div className="grid grid-cols-3 gap-2">
                <Skeleton className="h-32 rounded-lg" />
                <Skeleton className="h-32 rounded-lg" />
                <Skeleton className="h-32 rounded-lg" />
            </div>
            <Skeleton className="h-40 w-full rounded-lg" />
        </div>
    )
}
