/**
 * Dashboard widget model, ported from
 * apps/native/lib/components/dashboard/dashboard_models.dart and
 * dashboard_layout.dart so both clients read the same `options` JSON and lay
 * tiles out on the same 6-unit grid.
 */

export const WIDGET_TYPES = [
    'stat',
    'list',
    'balance',
    'chart',
    'balance_comparison',
] as const
export type WidgetType = (typeof WIDGET_TYPES)[number]

/**
 * The widgets that read account balances rather than transactions: they are
 * scoped by `currency` + `accountIds` and never carry a saved filter. The
 * balance card shows the balance now; the balance comparison shows last
 * month's closing balance, the current one, and the difference.
 */
export function isBalanceWidgetType(type: string): boolean {
    return type === 'balance' || type === 'balance_comparison'
}

/**
 * The as-of bound of "last month's balance" for a balance comparison: the
 * local midnight that starts the month `now` is in. Balances are read with an
 * exclusive bound, so every movement of the previous month's last day counts.
 * Computed on the device, so the month boundary is the device's calendar.
 */
export function monthCloseAsOfMs(now: Date): number {
    return new Date(now.getFullYear(), now.getMonth(), 1).getTime()
}

export const DASHBOARD_WIDTHS = ['full', 'two_thirds', 'half', 'third'] as const
export type DashboardWidth = (typeof DASHBOARD_WIDTHS)[number]

/** The dashboard grid is this many columns wide. */
export const GRID_UNITS = 6

export const WIDTH_UNITS: Record<DashboardWidth, number> = {
    full: GRID_UNITS,
    two_thirds: 4,
    half: 3,
    third: 2,
}

/** The widest width fitting in `maxUnits`, or null when not even a third fits. */
export function widthForUnits(maxUnits: number): DashboardWidth | null {
    for (const width of DASHBOARD_WIDTHS) {
        if (WIDTH_UNITS[width] <= maxUnits) return width
    }
    return null
}

export const STAT_AGGREGATIONS = ['sum', 'net', 'count'] as const
export type StatAggregation = (typeof STAT_AGGREGATIONS)[number]

export const BREAKDOWN_GROUP_BYS = ['category', 'account', 'month'] as const
export type BreakdownGroupBy = (typeof BREAKDOWN_GROUP_BYS)[number]

export const BREAKDOWN_CHART_KINDS = ['pie', 'bar', 'line'] as const
export type BreakdownChartKind = (typeof BREAKDOWN_CHART_KINDS)[number]

export const BACKGROUND_MODES = ['none', 'fixed', 'value'] as const
export type BackgroundMode = (typeof BACKGROUND_MODES)[number]

export type ValueBackground = {
    low: number
    high: number
    lowColor: string
    betweenColor: string
    highColor: string
}

export type BackgroundStyle = {
    mode: BackgroundMode
    fixedColor: string | null
    value: ValueBackground | null
}

export const NO_BACKGROUND: BackgroundStyle = {
    mode: 'none',
    fixedColor: null,
    value: null,
}

/** Matches `DashboardValueBackground.defaults` on native. */
export const DEFAULT_VALUE_BACKGROUND: ValueBackground = {
    low: 0,
    high: 10000,
    lowColor: '#EF4444',
    betweenColor: '#FFCA28',
    highColor: '#69F0AE',
}

export type LayoutCoord = { row: number; col: number }

export type WidgetOptions = {
    title: string
    aggregation: StatAggregation
    limit: number
    currency: string
    /**
     * Balance card: the accounts it sums, all of them within `currency`. Empty
     * means "every account in `currency`" — the only shape written before
     * account scoping existed, so an old card keeps reading as a currency
     * total rather than as an empty selection summing to zero.
     */
    accountIds: string[]
    groupBy: BreakdownGroupBy
    chartKind: BreakdownChartKind
    background: BackgroundStyle
    layout: LayoutCoord | null
    /** Keys written by other clients, preserved verbatim on every write. */
    rest: Record<string, unknown>
}

/** Keys owned by the content editor — cleared before merging a content edit. */
const CONTENT_KEYS = [
    'title',
    'aggregation',
    'limit',
    'currency',
    'accountIds',
    'groupBy',
    'chartKind',
    'background',
] as const

function asRecord(value: unknown): Record<string, unknown> | null {
    return typeof value === 'object' && value !== null && !Array.isArray(value)
        ? (value as Record<string, unknown>)
        : null
}

function decodeOptions(raw: string): Record<string, unknown> {
    if (!raw) return {}
    try {
        return asRecord(JSON.parse(raw)) ?? {}
    } catch {
        return {}
    }
}

function oneOf<T extends string>(
    allowed: readonly T[],
    value: unknown,
    fallback: T,
): T {
    return allowed.includes(value as T) ? (value as T) : fallback
}

function backgroundFromJson(raw: unknown): BackgroundStyle {
    const record = asRecord(raw)
    if (!record) return NO_BACKGROUND
    const mode = oneOf(BACKGROUND_MODES, record.mode, 'none')
    const valueRecord = asRecord(record.value)
    return {
        mode,
        fixedColor:
            typeof record.fixedColor === 'string' ? record.fixedColor : null,
        value: valueRecord
            ? {
                  low: numberOr(valueRecord.low, DEFAULT_VALUE_BACKGROUND.low),
                  high: numberOr(
                      valueRecord.high,
                      DEFAULT_VALUE_BACKGROUND.high,
                  ),
                  lowColor: stringOr(
                      valueRecord.lowColor,
                      DEFAULT_VALUE_BACKGROUND.lowColor,
                  ),
                  betweenColor: stringOr(
                      valueRecord.betweenColor,
                      DEFAULT_VALUE_BACKGROUND.betweenColor,
                  ),
                  highColor: stringOr(
                      valueRecord.highColor,
                      DEFAULT_VALUE_BACKGROUND.highColor,
                  ),
              }
            : null,
    }
}

function numberOr(value: unknown, fallback: number): number {
    return typeof value === 'number' && Number.isFinite(value)
        ? value
        : fallback
}

function stringOr(value: unknown, fallback: string): string {
    return typeof value === 'string' && value ? value : fallback
}

/**
 * A stored id list, de-duplicated and stripped of anything that isn't a
 * non-empty string. Sync input is untrusted, so a malformed entry is dropped
 * rather than carried into a query argument.
 */
function idListFromJson(raw: unknown): string[] {
    if (!Array.isArray(raw)) return []
    const ids: string[] = []
    for (const entry of raw) {
        if (typeof entry !== 'string' || entry === '') continue
        if (!ids.includes(entry)) ids.push(entry)
    }
    return ids
}

function layoutFromJson(raw: unknown): LayoutCoord | null {
    const record = asRecord(raw)
    if (!record) return null
    const { row, col } = record
    if (typeof row !== 'number' || typeof col !== 'number') return null
    if (!Number.isInteger(row) || !Number.isInteger(col)) return null
    if (row < 0 || col < 0 || col >= GRID_UNITS) return null
    return { row, col }
}

export function parseWidgetOptions(raw: string): WidgetOptions {
    const decoded = decodeOptions(raw)
    const rest: Record<string, unknown> = { ...decoded }
    for (const key of [...CONTENT_KEYS, 'layout']) delete rest[key]
    return {
        title: typeof decoded.title === 'string' ? decoded.title : '',
        aggregation: oneOf(STAT_AGGREGATIONS, decoded.aggregation, 'sum'),
        limit:
            typeof decoded.limit === 'number' &&
            Number.isFinite(decoded.limit) &&
            decoded.limit > 0
                ? Math.trunc(decoded.limit)
                : 5,
        currency: typeof decoded.currency === 'string' ? decoded.currency : '',
        accountIds: idListFromJson(decoded.accountIds),
        groupBy: oneOf(BREAKDOWN_GROUP_BYS, decoded.groupBy, 'category'),
        chartKind: oneOf(BREAKDOWN_CHART_KINDS, decoded.chartKind, 'pie'),
        background: backgroundFromJson(decoded.background),
        layout: layoutFromJson(decoded.layout),
        rest,
    }
}

export function backgroundToJson(
    style: BackgroundStyle,
): Record<string, unknown> | null {
    switch (style.mode) {
        case 'none':
            return null
        case 'fixed':
            return {
                mode: 'fixed',
                fixedColor:
                    style.fixedColor ?? DEFAULT_VALUE_BACKGROUND.highColor,
            }
        case 'value':
            return {
                mode: 'value',
                value: style.value ?? DEFAULT_VALUE_BACKGROUND,
            }
    }
}

/**
 * Merges content-editor changes into the existing opaque options JSON. Layout
 * and forward-compatible keys survive; the previous type's content keys are
 * dropped so changing a widget's type leaves no stale values behind.
 */
export function mergeWidgetOptions(
    existing: string,
    changes: Record<string, unknown>,
): string {
    const merged = decodeOptions(existing)
    for (const key of CONTENT_KEYS) delete merged[key]
    for (const [key, value] of Object.entries(changes)) {
        if (value === null || value === undefined) continue
        merged[key] = value
    }
    return JSON.stringify(merged)
}

/** Writes a manual placement into the options JSON, leaving everything else. */
export function writeLayout(existing: string, coord: LayoutCoord): string {
    const merged = decodeOptions(existing)
    merged.layout = { row: coord.row, col: coord.col }
    return JSON.stringify(merged)
}

export type PlacementInput = {
    id: string
    width: DashboardWidth
    coord: LayoutCoord | null
}

export type WidgetPlacement = {
    id: string
    row: number
    col: number
    width: DashboardWidth
}

export type PlacementResolution = {
    placements: WidgetPlacement[]
    /** True when the stored snapshot was invalid and the legacy flow was used. */
    needsRepair: boolean
}

/**
 * Resolves stored coordinates into placements. Persisted coordinates are
 * untrusted sync input: a missing, duplicated, out-of-grid or overlapping
 * coordinate discards the whole snapshot in favour of the deterministic legacy
 * auto-flow, exactly as `resolvePlacementSnapshot` does on native.
 */
export function resolvePlacements(
    inputs: PlacementInput[],
): PlacementResolution {
    const stored: WidgetPlacement[] = []
    const ids = new Set<string>()
    const occupiedByRow = new Map<number, boolean[]>()

    for (const input of inputs) {
        const coord = input.coord
        if (coord === null || ids.has(input.id)) {
            return { placements: legacyFlow(inputs), needsRepair: true }
        }
        ids.add(input.id)
        const units = WIDTH_UNITS[input.width]
        if (coord.row < 0 || coord.col < 0 || coord.col + units > GRID_UNITS) {
            return { placements: legacyFlow(inputs), needsRepair: true }
        }
        let occupied = occupiedByRow.get(coord.row)
        if (!occupied) {
            occupied = new Array<boolean>(GRID_UNITS).fill(false)
            occupiedByRow.set(coord.row, occupied)
        }
        for (let unit = coord.col; unit < coord.col + units; unit++) {
            if (occupied[unit]) {
                return { placements: legacyFlow(inputs), needsRepair: true }
            }
            occupied[unit] = true
        }
        stored.push({
            id: input.id,
            row: coord.row,
            col: coord.col,
            width: input.width,
        })
    }

    return { placements: stored, needsRepair: false }
}

/** Narrow tiles flow left-to-right and wrap; a `full` tile always owns its row. */
function legacyFlow(inputs: PlacementInput[]): WidgetPlacement[] {
    const out: WidgetPlacement[] = []
    let row = 0
    let used = 0
    for (const input of inputs) {
        const units = WIDTH_UNITS[input.width]
        if (units >= GRID_UNITS) {
            if (used > 0) {
                row++
                used = 0
            }
            out.push({ id: input.id, row, col: 0, width: input.width })
            row++
            continue
        }
        if (used + units > GRID_UNITS) {
            row++
            used = 0
        }
        out.push({ id: input.id, row, col: used, width: input.width })
        used += units
        if (used === GRID_UNITS) {
            row++
            used = 0
        }
    }
    return out
}

/**
 * Renumbers rows so they are contiguous from 0 — the "empty rows collapse"
 * rule. Column gaps within a row are kept.
 */
export function collapseEmptyRows(
    placements: WidgetPlacement[],
): WidgetPlacement[] {
    const rows = [...new Set(placements.map((p) => p.row))].sort(
        (a, b) => a - b,
    )
    const remap = new Map(rows.map((row, index) => [row, index]))
    return placements.map((p) => ({ ...p, row: remap.get(p.row) ?? p.row }))
}

/** Whether `[col, col + units)` on `row` is free of everything but `exceptId`. */
export function isSpanFree(
    placements: WidgetPlacement[],
    row: number,
    col: number,
    units: number,
    exceptId?: string,
): boolean {
    if (col < 0 || col + units > GRID_UNITS) return false
    return !placements.some(
        (p) =>
            p.id !== exceptId &&
            p.row === row &&
            col < p.col + WIDTH_UNITS[p.width] &&
            p.col < col + units,
    )
}
