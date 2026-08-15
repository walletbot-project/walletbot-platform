/**
 * The canonical transaction-filter condition tree stored in
 * `savedFilters.config`, ported from the native model
 * (apps/native/lib/data/models/transaction_filter.dart) so both clients and the
 * backend read and write exactly the same JSON. See docs/home-dashboard.md
 * § "Combination model — one canonical tree, two UIs".
 */

export const TXN_TYPES = [
    'expense',
    'income',
    'transfer',
    'balance_adjustment',
] as const
export type TxnType = (typeof TXN_TYPES)[number]

export const TXN_STATUSES = ['pending', 'cleared'] as const
export type TxnStatus = (typeof TXN_STATUSES)[number]

export const DATE_PRESETS = [
    'today',
    'this_week',
    'this_month',
    'last_month',
    'this_year',
] as const
export type DatePreset = (typeof DATE_PRESETS)[number]

export const ACCOUNT_DIRECTIONS = ['source', 'destination', 'either'] as const
export type AccountDirection = (typeof ACCOUNT_DIRECTIONS)[number]

export const TAG_MATCHES = ['any', 'all'] as const
export type TagMatch = (typeof TAG_MATCHES)[number]

export type FilterCondition = {
    field: string
    operator: string
    value: unknown
    direction?: AccountDirection
    match?: TagMatch
    includeSubtags?: boolean
}

export type FilterGroup = {
    combinator: 'and' | 'or'
    not?: boolean
    children: FilterNode[]
}

export type FilterNode = FilterGroup | FilterCondition

export function isFilterGroup(node: FilterNode): node is FilterGroup {
    return 'children' in node
}

/**
 * The flat, simple-mode view over the tree. Every field is optional; an empty
 * filter matches all transactions. `advancedRoot` is set only when the stored
 * tree cannot be faithfully flattened, in which case the flat fields are
 * meaningless and the tree is evaluated directly.
 */
export type SimpleFilter = {
    types: TxnType[]
    status: TxnStatus | null
    /** Relative preset, ignored when `dateFrom`/`dateTo` are set. */
    datePreset: DatePreset | null
    /** Absolute range as ISO date strings; takes precedence over the preset. */
    dateFrom: string | null
    dateTo: string | null
    accountIds: string[]
    accountDirection: AccountDirection
    categoryIds: string[]
    tagIds: string[]
    tagMatch: TagMatch
    includeSubtags: boolean
    currency: string | null
    amountMinCents: number | null
    amountMaxCents: number | null
    search: string | null
    advancedRoot: FilterGroup | null
}

export const EMPTY_FILTER: SimpleFilter = {
    types: [],
    status: null,
    datePreset: null,
    dateFrom: null,
    dateTo: null,
    accountIds: [],
    accountDirection: 'either',
    categoryIds: [],
    tagIds: [],
    tagMatch: 'any',
    includeSubtags: false,
    currency: null,
    amountMinCents: null,
    amountMaxCents: null,
    search: null,
    advancedRoot: null,
}

function asRecord(value: unknown): Record<string, unknown> | null {
    return typeof value === 'object' && value !== null && !Array.isArray(value)
        ? (value as Record<string, unknown>)
        : null
}

function asStringList(value: unknown): string[] {
    return Array.isArray(value)
        ? value.filter((item): item is string => typeof item === 'string')
        : []
}

function oneOf<T extends string>(
    allowed: readonly T[],
    value: unknown,
    fallback: T,
): T {
    return allowed.includes(value as T) ? (value as T) : fallback
}

export function filterNodeFromJson(value: unknown): FilterNode | null {
    const record = asRecord(value)
    if (!record) return null
    if ('children' in record) {
        const rawChildren = Array.isArray(record.children)
            ? record.children
            : []
        return {
            combinator: record.combinator === 'or' ? 'or' : 'and',
            ...(record.not === true ? { not: true } : {}),
            children: rawChildren
                .map(filterNodeFromJson)
                .filter((child): child is FilterNode => child !== null),
        }
    }
    return {
        field: typeof record.field === 'string' ? record.field : 'type',
        operator: typeof record.operator === 'string' ? record.operator : 'in',
        value: record.value,
        direction: oneOf(ACCOUNT_DIRECTIONS, record.direction, 'either'),
        match: oneOf(TAG_MATCHES, record.match, 'any'),
        includeSubtags: record.includeSubtags === true,
    }
}

function rootFromJson(value: unknown): FilterGroup {
    const node = filterNodeFromJson(value)
    if (node === null) return { combinator: 'and', children: [] }
    return isFilterGroup(node) ? node : { combinator: 'and', children: [node] }
}

/**
 * Whether a tree is representable by the flat simple-mode fields: a single
 * top-level `and`, depth 1, one condition per field, no `not`.
 */
export function isSimplyRepresentable(root: FilterGroup): boolean {
    if (root.combinator !== 'and' || root.not === true) return false
    const seen = new Set<string>()
    for (const child of root.children) {
        if (isFilterGroup(child)) return false
        if (seen.has(child.field)) return false
        seen.add(child.field)
        switch (child.field) {
            case 'type':
            case 'status':
            case 'account':
            case 'category':
            case 'tag':
            case 'currency':
                if (child.operator !== 'in') return false
                break
            case 'date':
                if (
                    child.operator !== 'relative' &&
                    child.operator !== 'between'
                ) {
                    return false
                }
                break
            case 'amount':
                if (child.operator !== 'between') return false
                break
            case 'text':
                if (child.operator !== 'contains') return false
                break
            default:
                return false
        }
    }
    return true
}

/** Parses a stored `savedFilters.config` JSON string into a `SimpleFilter`. */
export function parseFilterConfig(config: string): SimpleFilter {
    if (!config) return EMPTY_FILTER
    let decoded: unknown
    try {
        decoded = JSON.parse(config)
    } catch {
        return EMPTY_FILTER
    }
    return filterFromCanonical(decoded)
}

export function filterFromCanonical(value: unknown): SimpleFilter {
    const root = rootFromJson(value)
    if (!isSimplyRepresentable(root)) {
        return { ...EMPTY_FILTER, advancedRoot: root }
    }

    const filter: SimpleFilter = { ...EMPTY_FILTER }
    for (const child of root.children) {
        if (isFilterGroup(child)) continue
        switch (child.field) {
            case 'type':
                filter.types = asStringList(child.value).filter(
                    (wire): wire is TxnType =>
                        TXN_TYPES.includes(wire as TxnType),
                )
                break
            case 'status': {
                const wire = asStringList(child.value)[0]
                filter.status = TXN_STATUSES.includes(wire as TxnStatus)
                    ? (wire as TxnStatus)
                    : null
                break
            }
            case 'date':
                if (
                    child.operator === 'relative' &&
                    typeof child.value === 'string'
                ) {
                    filter.datePreset = DATE_PRESETS.includes(
                        child.value as DatePreset,
                    )
                        ? (child.value as DatePreset)
                        : null
                } else if (child.operator === 'between') {
                    const range = asRecord(child.value)
                    if (
                        range &&
                        typeof range.from === 'string' &&
                        typeof range.to === 'string'
                    ) {
                        filter.dateFrom = range.from
                        filter.dateTo = range.to
                    }
                }
                break
            case 'account':
                filter.accountIds = asStringList(child.value)
                filter.accountDirection = child.direction ?? 'either'
                break
            case 'category':
                filter.categoryIds = asStringList(child.value)
                break
            case 'tag':
                filter.tagIds = asStringList(child.value)
                filter.tagMatch = child.match ?? 'any'
                filter.includeSubtags = child.includeSubtags === true
                break
            case 'currency':
                filter.currency = asStringList(child.value)[0] ?? null
                break
            case 'amount': {
                const range = asRecord(child.value)
                if (range) {
                    if (typeof range.min === 'number') {
                        filter.amountMinCents = range.min
                    }
                    if (typeof range.max === 'number') {
                        filter.amountMaxCents = range.max
                    }
                }
                break
            }
            case 'text':
                if (typeof child.value === 'string') filter.search = child.value
                break
        }
    }
    return filter
}

/** Serializes a `SimpleFilter` back to the canonical tree. */
export function filterToCanonical(filter: SimpleFilter): FilterGroup {
    if (filter.advancedRoot) return filter.advancedRoot

    const children: FilterCondition[] = []
    if (filter.types.length > 0) {
        children.push({ field: 'type', operator: 'in', value: filter.types })
    }
    if (filter.status) {
        children.push({
            field: 'status',
            operator: 'in',
            value: [filter.status],
        })
    }
    if (filter.dateFrom && filter.dateTo) {
        children.push({
            field: 'date',
            operator: 'between',
            value: { from: filter.dateFrom, to: filter.dateTo },
        })
    } else if (filter.datePreset) {
        children.push({
            field: 'date',
            operator: 'relative',
            value: filter.datePreset,
        })
    }
    if (filter.accountIds.length > 0) {
        children.push({
            field: 'account',
            operator: 'in',
            value: filter.accountIds,
            direction: filter.accountDirection,
        })
    }
    if (filter.categoryIds.length > 0) {
        children.push({
            field: 'category',
            operator: 'in',
            value: filter.categoryIds,
        })
    }
    if (filter.tagIds.length > 0) {
        children.push({
            field: 'tag',
            operator: 'in',
            value: filter.tagIds,
            match: filter.tagMatch,
            includeSubtags: filter.includeSubtags,
        })
    }
    if (filter.currency) {
        children.push({
            field: 'currency',
            operator: 'in',
            value: [filter.currency],
        })
        if (filter.amountMinCents !== null || filter.amountMaxCents !== null) {
            children.push({
                field: 'amount',
                operator: 'between',
                value: {
                    min: filter.amountMinCents,
                    max: filter.amountMaxCents,
                },
            })
        }
    }
    const search = filter.search?.trim()
    if (search) {
        children.push({ field: 'text', operator: 'contains', value: search })
    }
    return { combinator: 'and', children }
}

export function filterConfigToJson(filter: SimpleFilter): string {
    return JSON.stringify(filterToCanonical(filter))
}

/** Resolved query window: `date >= fromMs && date < toExclusiveMs`. */
export type DateWindow = { fromMs: number | null; toExclusiveMs: number | null }

function dayStart(date: Date): Date {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

/**
 * Resolves the date dimension to an absolute window, matching the native
 * `resolveDateWindow`: absolute ranges are day-precision with an inclusive end
 * day, and weeks start on Monday.
 */
export function resolveDateWindow(
    filter: SimpleFilter,
    now: Date = new Date(),
): DateWindow | null {
    if (filter.dateFrom && filter.dateTo) {
        const from = new Date(filter.dateFrom)
        const to = new Date(filter.dateTo)
        if (!Number.isNaN(from.getTime()) && !Number.isNaN(to.getTime())) {
            const endExclusive = dayStart(to)
            endExclusive.setDate(endExclusive.getDate() + 1)
            return {
                fromMs: dayStart(from).getTime(),
                toExclusiveMs: endExclusive.getTime(),
            }
        }
    }
    const preset = filter.datePreset
    if (!preset) return null
    const today = dayStart(now)
    switch (preset) {
        case 'today': {
            const end = new Date(today)
            end.setDate(end.getDate() + 1)
            return { fromMs: today.getTime(), toExclusiveMs: end.getTime() }
        }
        case 'this_week': {
            // ISO weeks start on Monday; JS `getDay()` is Sunday-based.
            const weekday = (today.getDay() + 6) % 7
            const start = new Date(today)
            start.setDate(start.getDate() - weekday)
            const end = new Date(start)
            end.setDate(end.getDate() + 7)
            return { fromMs: start.getTime(), toExclusiveMs: end.getTime() }
        }
        case 'this_month':
            return {
                fromMs: new Date(
                    now.getFullYear(),
                    now.getMonth(),
                    1,
                ).getTime(),
                toExclusiveMs: new Date(
                    now.getFullYear(),
                    now.getMonth() + 1,
                    1,
                ).getTime(),
            }
        case 'last_month':
            return {
                fromMs: new Date(
                    now.getFullYear(),
                    now.getMonth() - 1,
                    1,
                ).getTime(),
                toExclusiveMs: new Date(
                    now.getFullYear(),
                    now.getMonth(),
                    1,
                ).getTime(),
            }
        case 'this_year':
            return {
                fromMs: new Date(now.getFullYear(), 0, 1).getTime(),
                toExclusiveMs: new Date(now.getFullYear() + 1, 0, 1).getTime(),
            }
    }
}

/** Every tag condition in the tree, so callers can pre-resolve tag membership. */
export function collectTagConditions(root: FilterGroup): FilterCondition[] {
    const out: FilterCondition[] = []
    const walk = (node: FilterNode) => {
        if (isFilterGroup(node)) {
            node.children.forEach(walk)
            return
        }
        if (node.field === 'tag') out.push(node)
    }
    walk(root)
    return out
}
