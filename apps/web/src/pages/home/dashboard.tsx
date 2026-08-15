import { api } from '@wallet-bot/backend/api'
import {
    collapseEmptyRows,
    type DashboardWidth,
    GRID_UNITS,
    isSpanFree,
    type PlacementInput,
    parseFilterConfig,
    parseWidgetOptions,
    resolvePlacements,
    WIDTH_UNITS,
    type WidgetPlacement,
    writeLayout,
} from '@wallet-bot/shared'
import { IconButton } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { toast } from 'sonner'
import { Icon } from '@/components/m3/icon'
import { Skeleton } from '@/components/ui/skeleton'
import { useElementWidth } from '@/hooks/use-element-width'
import { type Messages, useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'
import { defaultDashboardSeed } from '@/pages/home/default-dashboard'
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

type LayoutRow = {
    id: string
    type: string
    filterId: string | null
    position: number
    width: string
    options: string
}

export type DashboardWidgetRow = LayoutRow

/**
 * The home dashboard: the manual 6-unit grid of configured widgets, ported
 * from the native `DashboardSection` (docs/home-dashboard.md § "Layout: manual
 * grid").
 *
 * Editing is the same set of affordances the native floating tile menu offers —
 * width controls, one-cell nudges and delete — driven by the shared layout
 * engine in `@wallet-bot/shared`, so both clients resolve and repair a stored
 * layout identically.
 */
export function Dashboard({
    editing,
    onStartEditing,
    onEditWidget,
}: {
    editing: boolean
    onStartEditing: () => void
    onEditWidget: (widget: LayoutRow) => void
}) {
    const t = useT()
    const layout = useQuery(api.v1.dashboard.queries.layout)
    const seed = useMutation(api.v1.dashboard.mutations.seedDefaultIfEmpty)
    const saveLayout = useMutation(api.v1.dashboard.mutations.saveLayout)
    const archiveWidget = useMutation(api.v1.dashboard.mutations.archiveWidget)
    const seededRef = useRef(false)
    const [measureRef, width] = useElementWidth()
    // Only the selected tile shows its floating menu. Derived rather than
    // cleared in an effect, which is also exactly how native reads it:
    // `selected = editing && selectedItemId == item.row.id`.
    const [pickedId, setSelectedId] = useState<string | null>(null)
    const selectedId = editing ? pickedId : null

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

    const specs = useMemo(() => {
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

    const placements = useMemo(() => {
        const inputs: PlacementInput[] = specs.map(({ row, spec }) => ({
            id: row.id,
            width: normalizeWidth(row.width),
            coord: spec.options.layout,
        }))
        return resolvePlacements(inputs).placements
    }, [specs])

    const persist = useCallback(
        async (next: WidgetPlacement[]) => {
            const collapsed = collapseEmptyRows(next)
            const ordered = [...collapsed].sort(
                (a, b) => a.row - b.row || a.col - b.col,
            )
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

    const rowCount = placements.reduce(
        (max, placement) => Math.max(max, placement.row + 1),
        0,
    )
    const specById = new Map(specs.map((entry) => [entry.spec.id, entry]))

    const renderRow = (rowIndex: number) => (
        <div
            className="grid"
            style={{
                gridTemplateColumns: `repeat(${GRID_UNITS}, minmax(0, 1fr))`,
                gap: TILE_GAP,
            }}
        >
            {placements
                .filter((placement) => placement.row === rowIndex)
                .sort((a, b) => a.col - b.col)
                .map((placement) => {
                    const entry = specById.get(placement.id)
                    if (!entry) return null
                    return (
                        <div
                            key={placement.id}
                            className="relative min-w-0"
                            style={{
                                gridColumn: `${placement.col + 1} / span ${WIDTH_UNITS[placement.width]}`,
                            }}
                        >
                            <WidgetBody spec={entry.spec} />
                            {editing ? (
                                <>
                                    {/*
                                     * In edit mode the tile is a selection
                                     * target, not a live widget — the same
                                     * thing the native `InkWell(onTap:
                                     * onTapItem)` does over the content.
                                     */}
                                    <button
                                        type="button"
                                        aria-pressed={
                                            placement.id === selectedId
                                        }
                                        aria-label={
                                            entry.spec.options.title ||
                                            t.dashboard.widget
                                        }
                                        onClick={() =>
                                            setSelectedId(placement.id)
                                        }
                                        className={cn(
                                            'absolute inset-0 cursor-pointer rounded-lg border-2',
                                            placement.id === selectedId
                                                ? 'border-primary'
                                                : 'border-transparent',
                                        )}
                                    />
                                    {placement.id === selectedId ? (
                                        <TileMenu
                                            placement={placement}
                                            placements={placements}
                                            onEdit={() =>
                                                onEditWidget(entry.row)
                                            }
                                            onDelete={async () => {
                                                try {
                                                    await archiveWidget({
                                                        id: placement.id,
                                                    })
                                                } catch {
                                                    toast.error(
                                                        t.dashboard
                                                            .deleteFailed,
                                                    )
                                                }
                                            }}
                                            onChange={persist}
                                        />
                                    ) : null}
                                </>
                            ) : null}
                        </div>
                    )
                })}
        </div>
    )

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

    if (bandColumns === 1) {
        return (
            <div
                ref={measureRef}
                className="flex flex-col"
                style={{ gap: TILE_GAP }}
            >
                {Array.from({ length: rowCount }, (_, rowIndex) => (
                    <div key={rowIndex}>{renderRow(rowIndex)}</div>
                ))}
            </div>
        )
    }

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
        </div>
    )
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

/**
 * The per-tile edit menu, porting `_DashboardFloatingMenu`: a row of `1/1 ·
 * 2/3 · 1/2 · 1/3` width chips followed by edit and delete, over a row of
 * one-cell nudges. A control that would not fit is disabled rather than
 * silently doing nothing.
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
    onDelete: () => Promise<void>
    onChange: (next: WidgetPlacement[]) => Promise<void>
}) {
    const t = useT()
    const units = WIDTH_UNITS[placement.width]

    const replace = (next: WidgetPlacement) =>
        placements.map((p) => (p.id === placement.id ? next : p))

    const canMove = (dx: number, dy: number) => {
        const row = placement.row + dy
        const col = placement.col + dx
        if (row < 0 || col < 0 || col + units > GRID_UNITS) return false
        return isSpanFree(placements, row, col, units, placement.id)
    }

    const move = (dx: number, dy: number) => {
        if (!canMove(dx, dy)) return
        void onChange(
            replace({
                ...placement,
                row: placement.row + dy,
                col: placement.col + dx,
            } satisfies WidgetPlacement),
        )
    }

    // Shrinking always fits; growing needs free units to the right.
    const canUseWidth = (candidate: DashboardWidth) =>
        WIDTH_UNITS[candidate] <= units ||
        isSpanFree(
            placements,
            placement.row,
            placement.col,
            WIDTH_UNITS[candidate],
            placement.id,
        )

    // The menu hangs just below the tile and anchors to whichever edge points
    // at the screen centre, so it grows inward instead of off the side —
    // `_FloatingMenuAnchor` + `_alignMenuRight`.
    const alignRight = placement.col + units / 2 > GRID_UNITS / 2

    return (
        <div
            className={cn(
                'absolute top-full z-30 pt-1.5',
                alignRight ? 'right-0' : 'left-0',
            )}
        >
            <div className="flex w-max flex-col items-center gap-0.5 rounded-lg bg-surface/96 px-1.5 py-1 shadow-level-4">
                <div className="flex items-center gap-1">
                    {WIDTH_OPTIONS.map((option) => (
                        <WidthChip
                            key={option}
                            label={widthChipLabel(option, t)}
                            selected={option === placement.width}
                            isDisabled={!canUseWidth(option)}
                            onClick={() =>
                                void onChange(
                                    replace({ ...placement, width: option }),
                                )
                            }
                        />
                    ))}
                    <TileAction
                        icon="tune"
                        label={t.common.edit}
                        onPress={onEdit}
                    />
                    <TileAction
                        icon="delete"
                        label={t.common.delete}
                        onPress={() => void onDelete()}
                        destructive
                    />
                </div>
                <div className="flex items-center">
                    <TileAction
                        icon="arrow_back"
                        label={t.dashboard.moveLeft}
                        onPress={() => move(-1, 0)}
                        isDisabled={!canMove(-1, 0)}
                    />
                    <TileAction
                        icon="arrow_upward"
                        label={t.dashboard.moveUp}
                        onPress={() => move(0, -1)}
                        isDisabled={!canMove(0, -1)}
                    />
                    <TileAction
                        icon="arrow_downward"
                        label={t.dashboard.moveDown}
                        onPress={() => move(0, 1)}
                        isDisabled={!canMove(0, 1)}
                    />
                    <TileAction
                        icon="arrow_forward"
                        label={t.dashboard.moveRight}
                        onPress={() => move(1, 0)}
                        isDisabled={!canMove(1, 0)}
                    />
                </div>
            </div>
        </div>
    )
}

function widthChipLabel(width: DashboardWidth, t: Messages): string {
    switch (width) {
        case 'full':
            return t.dashboard.widthFull
        case 'two_thirds':
            return t.dashboard.widthTwoThirds
        case 'half':
            return t.dashboard.widthHalf
        case 'third':
            return t.dashboard.widthThird
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
