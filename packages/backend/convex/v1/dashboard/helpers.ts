import {
    collectTagConditions,
    type DateWindow,
    type FilterCondition,
    type FilterGroup,
    type FilterNode,
    isFilterGroup,
    parseFilterConfig,
    parseFilterConfigRoot,
    resolveDateConditionWindow,
    resolveDateWindow,
    type SimpleFilter,
} from '@wallet-bot/shared'
import type { IndexRange, NamedTableInfo, Query } from 'convex/server'
import type { DataModel, Doc } from '../../_generated/dataModel'
import type { QueryCtx } from '../../_generated/server'

/**
 * Server-side evaluation of the canonical filter tree
 * (docs/home-dashboard.md § "Querying & indexes").
 *
 * The strategy the doc prescribes is **bound the scan with an index, then
 * predicate-filter the residual**: pick the narrowest available index range
 * from the filter's anchor dimensions (date window first, then a single
 * account or category), stream it newest-first, and evaluate the full tree as
 * a predicate over that bounded window. Tag membership is pre-resolved into
 * id sets so the predicate never issues per-row reads.
 */

/** Hard bound on the index range a single widget query may walk. */
export const MAX_SCAN = 2000

/**
 * Both dashboard tables are per-user configuration: a handful of rows each,
 * bounded by what a person can lay out on one screen. The cap is a guard, not
 * a paging strategy.
 */
export const MAX_DASHBOARD_ROWS = 200

export type Transaction = Doc<'transactions'>

export type EvaluationContext = {
    /** transactionId -> the tag ids on it, for the tag conditions in the tree. */
    tagsByTransaction: Map<string, Set<string>>
    /**
     * tagId -> itself plus every descendant, resolved for the conditions that
     * set `includeSubtags` — native's `expandTagGroups` groups.
     */
    tagDescendants: Map<string, Set<string>>
    now: Date
    /**
     * Exclusive upper bound on `date` for the rows a read may see — the
     * occurrence cutoff. It rides in the evaluation context so that
     * `collectMatching`, the single door every dashboard read goes through,
     * cannot be called without one.
     */
    asOfMs: bigint
}

export function filterFromConfig(config: string | null | undefined): {
    filter: SimpleFilter
    root: FilterGroup
} {
    // The stored tree is evaluated as-is; the flat view only picks the index
    // anchors. Re-serializing the flat view and evaluating that (the previous
    // approach) silently dropped whatever flattening loses — extra status
    // values, an amount bound without a currency, a one-sided date range.
    return {
        filter: parseFilterConfig(config ?? ''),
        root: parseFilterConfigRoot(config ?? ''),
    }
}

/**
 * Expands the selected tags to their descendants when `includeSubtags` is set,
 * then resolves the transactions carrying them. Runs once per query, before the
 * scan, so the predicate is a pure set membership test.
 */
export async function buildEvaluationContext(
    ctx: QueryCtx,
    userId: string,
    root: FilterGroup,
    now: Date,
    asOfMs: bigint,
): Promise<EvaluationContext> {
    const conditions = collectTagConditions(root)
    const tagsByTransaction = new Map<string, Set<string>>()
    const tagDescendants = new Map<string, Set<string>>()
    if (conditions.length === 0)
        return { tagsByTransaction, tagDescendants, now, asOfMs }

    const wanted = new Set<string>()
    for (const condition of conditions) {
        const ids = Array.isArray(condition.value)
            ? condition.value.filter(
                  (id): id is string => typeof id === 'string',
              )
            : []
        for (const id of ids) wanted.add(id)
    }
    if (wanted.size === 0)
        return { tagsByTransaction, tagDescendants, now, asOfMs }

    // The ids whose joins must be loaded: the literal selections, plus their
    // descendants when some condition expands subtags.
    const joinIds = new Set(wanted)
    if (conditions.some((condition) => condition.includeSubtags === true)) {
        // Descendants are resolved from the user's own tag list, which is small
        // and already read whole by the tags screen.
        const tags = await ctx.db
            .query('tags')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .take(MAX_SCAN)
        const childrenByParent = new Map<string, string[]>()
        for (const tag of tags) {
            if (!tag.parentId) continue
            const siblings = childrenByParent.get(tag.parentId) ?? []
            siblings.push(tag.id)
            childrenByParent.set(tag.parentId, siblings)
        }
        // One group per selected tag — the tag plus all its descendants —
        // matching native's `expandTagGroups`, so a `match: all` condition can
        // require a hit in *every* group rather than in a merged union.
        for (const id of wanted) {
            const group = new Set([id])
            const queue = [id]
            while (queue.length > 0) {
                const current = queue.pop()
                if (current === undefined) break
                for (const child of childrenByParent.get(current) ?? []) {
                    if (!group.has(child)) {
                        group.add(child)
                        queue.push(child)
                    }
                }
            }
            tagDescendants.set(id, group)
            for (const member of group) joinIds.add(member)
        }
    }

    for (const tagId of joinIds) {
        const joins = await ctx.db
            .query('transactionTags')
            .withIndex('by_user_tag', (q) =>
                q.eq('userId', userId).eq('tagId', tagId),
            )
            .take(MAX_SCAN)
        for (const join of joins) {
            const set = tagsByTransaction.get(join.transactionId) ?? new Set()
            set.add(join.tagId)
            tagsByTransaction.set(join.transactionId, set)
        }
    }
    return { tagsByTransaction, tagDescendants, now, asOfMs }
}

export type MatchResult = {
    rows: Transaction[]
    /** True when an index scan hit `MAX_SCAN` before its window was exhausted. */
    truncated: boolean
}

/** An index builder once every equality prefix is applied and `date` is next. */
export type DateRangeBuilder = {
    gte(
        fieldName: 'date',
        value: bigint,
    ): { lte(fieldName: 'date', value: bigint): IndexRange } & IndexRange
    lte(fieldName: 'date', value: bigint): IndexRange
} & IndexRange

/**
 * Narrows a window to the already-happened side of `asOfMs`.
 *
 * A recurring rule materialises its occurrences as ordinary transactions with
 * future dates, so every read that describes what happened has to stop here.
 * Folding the cutoff into the window means it rides the same index range as
 * the user's own date filter — it costs nothing and, crucially, it cannot be
 * forgotten by a caller that already bounds by date.
 *
 * `asOfMs` is the exclusive upper bound (the end of the current occurrence
 * block); see `pastCutoffMs` in `@wallet-bot/shared` for why it travels as an
 * argument instead of being read off the server clock.
 */
export function occurredWindow(
    window: DateWindow | null,
    asOfMs: bigint,
): DateWindow {
    const cutoff = Number(asOfMs)
    const toExclusiveMs =
        window?.toExclusiveMs === null || window?.toExclusiveMs === undefined
            ? cutoff
            : Math.min(window.toExclusiveMs, cutoff)
    return { fromMs: window?.fromMs ?? null, toExclusiveMs }
}

export function boundByDate(
    base: DateRangeBuilder,
    window: DateWindow | null,
): IndexRange {
    const fromMs = window?.fromMs ?? null
    // The stored window is half-open; the index range is inclusive, so step
    // back one millisecond rather than widening the range by a day.
    const toMs =
        window?.toExclusiveMs === null || window?.toExclusiveMs === undefined
            ? null
            : window.toExclusiveMs - 1
    if (fromMs !== null && toMs !== null) {
        return base.gte('date', BigInt(fromMs)).lte('date', BigInt(toMs))
    }
    if (fromMs !== null) return base.gte('date', BigInt(fromMs))
    if (toMs !== null) return base.lte('date', BigInt(toMs))
    return base
}

/**
 * The date window bounding the index scan. Simple filters carry it in their
 * flat fields; an advanced tree contributes one when a date condition sits
 * directly under the top-level `and` — every match must satisfy it, so
 * bounding the scan by it is sound. `or`/negated roots get no bound; their
 * date conditions are still enforced row by row by the predicate.
 */
export function indexDateWindow(
    filter: SimpleFilter,
    root: FilterGroup,
    now: Date,
): DateWindow | null {
    const flat = resolveDateWindow(filter, now)
    if (flat) return flat
    if (root.combinator !== 'and' || root.not === true) return null
    for (const child of root.children) {
        if (isFilterGroup(child) || child.field !== 'date') continue
        const window = resolveDateConditionWindow(child, now)
        if (window) return window
    }
    return null
}

type TxnQuery = Query<NamedTableInfo<DataModel, 'transactions'>>

async function scanStream(
    stream: TxnQuery,
    root: FilterGroup,
    evaluation: EvaluationContext,
    limit: number | null,
): Promise<MatchResult> {
    const rows: Transaction[] = []
    let scanned = 0
    for await (const txn of stream.order('desc')) {
        scanned++
        if (scanned > MAX_SCAN) return { rows, truncated: true }
        if (txn.isArchived) continue
        if (matchesNode(txn, root, evaluation)) {
            rows.push(txn)
            if (limit !== null && rows.length >= limit) break
        }
    }
    return { rows, truncated: false }
}

/**
 * Walks the index range the filter's anchor bounds, newest-first, keeping the
 * rows the tree matches. `limit` stops the walk as soon as enough rows are
 * collected; aggregations pass `null` to consume the whole bounded window.
 */
export async function collectMatching(
    ctx: QueryCtx,
    userId: string,
    filter: SimpleFilter,
    root: FilterGroup,
    evaluation: EvaluationContext,
    limit: number | null,
): Promise<MatchResult> {
    const window = occurredWindow(
        indexDateWindow(filter, root, evaluation.now),
        evaluation.asOfMs,
    )

    const anchorAccount =
        filter.accountIds.length === 1 ? filter.accountIds[0] : null
    const anchorCategory =
        filter.categoryIds.length === 1 ? filter.categoryIds[0] : null

    const bySource = (accountId: string) =>
        ctx.db
            .query('transactions')
            .withIndex('by_user_account_date', (q) =>
                boundByDate(
                    q.eq('userId', userId).eq('accountId', accountId),
                    window,
                ),
            )
    const byDestination = (accountId: string) =>
        ctx.db
            .query('transactions')
            .withIndex('by_user_to_account_date', (q) =>
                boundByDate(
                    q.eq('userId', userId).eq('toAccountId', accountId),
                    window,
                ),
            )

    const streams: TxnQuery[] =
        anchorAccount !== null
            ? filter.accountDirection === 'source'
                ? [bySource(anchorAccount)]
                : filter.accountDirection === 'destination'
                  ? [byDestination(anchorAccount)]
                  : // `either`: the account can sit on either leg and each leg
                    // has its own index — scan both and merge, so transfers
                    // *into* the account are not silently dropped.
                    [bySource(anchorAccount), byDestination(anchorAccount)]
            : anchorCategory !== null
              ? [
                    ctx.db
                        .query('transactions')
                        .withIndex('by_user_category_date', (q) =>
                            boundByDate(
                                q
                                    .eq('userId', userId)
                                    .eq('categoryId', anchorCategory),
                                window,
                            ),
                        ),
                ]
              : [
                    ctx.db
                        .query('transactions')
                        .withIndex('by_user_date', (q) =>
                            boundByDate(q.eq('userId', userId), window),
                        ),
                ]

    if (streams.length === 1) {
        return scanStream(streams[0], root, evaluation, limit)
    }

    // Each leg is already newest-first and capped; the union's newest `limit`
    // rows are therefore contained in the legs' own top `limit` rows.
    const results = await Promise.all(
        streams.map((stream) => scanStream(stream, root, evaluation, limit)),
    )
    const byId = new Map<string, Transaction>()
    for (const result of results) {
        for (const txn of result.rows) byId.set(txn._id, txn)
    }
    const merged = [...byId.values()].sort((a, b) =>
        a.date === b.date ? 0 : a.date > b.date ? -1 : 1,
    )
    return {
        rows: limit !== null ? merged.slice(0, limit) : merged,
        truncated: results.some((result) => result.truncated),
    }
}

export function matchesNode(
    txn: Transaction,
    node: FilterNode,
    evaluation: EvaluationContext,
): boolean {
    if (isFilterGroup(node)) {
        const results = node.children.map((child) =>
            matchesNode(txn, child, evaluation),
        )
        const value =
            node.combinator === 'or'
                ? results.length === 0 || results.some(Boolean)
                : results.every(Boolean)
        return node.not === true ? !value : value
    }
    return matchesCondition(txn, node, evaluation)
}

function asStringList(value: unknown): string[] {
    return Array.isArray(value)
        ? value.filter((item): item is string => typeof item === 'string')
        : []
}

function matchesCondition(
    txn: Transaction,
    condition: FilterCondition,
    evaluation: EvaluationContext,
): boolean {
    const negate =
        condition.operator === 'not in' || condition.operator === 'not contains'
    const result = evaluateCondition(txn, condition, evaluation)
    return negate ? !result : result
}

function evaluateCondition(
    txn: Transaction,
    condition: FilterCondition,
    evaluation: EvaluationContext,
): boolean {
    switch (condition.field) {
        case 'type': {
            const values = asStringList(condition.value)
            return values.length === 0 || values.includes(txn.type)
        }
        case 'status': {
            const values = asStringList(condition.value)
            return values.length === 0 || values.includes(txn.status)
        }
        case 'date': {
            // Simple filters also serve this from the index range, but a date
            // condition anywhere in an advanced tree only exists here — the
            // counterpart of native's `_dateCondition`, which compiles every
            // date condition into the SQL predicate.
            const window = resolveDateConditionWindow(condition, evaluation.now)
            if (!window) return true
            if (window.fromMs !== null && txn.date < BigInt(window.fromMs)) {
                return false
            }
            if (
                window.toExclusiveMs !== null &&
                txn.date >= BigInt(window.toExclusiveMs)
            ) {
                return false
            }
            return true
        }
        case 'account': {
            const values = asStringList(condition.value)
            if (values.length === 0) return true
            const direction = condition.direction ?? 'either'
            const matchesSource = values.includes(txn.accountId)
            const matchesDestination =
                txn.toAccountId !== undefined &&
                values.includes(txn.toAccountId)
            if (direction === 'source') return matchesSource
            if (direction === 'destination') return matchesDestination
            return matchesSource || matchesDestination
        }
        case 'category': {
            const values = asStringList(condition.value)
            return (
                values.length === 0 ||
                (txn.categoryId !== undefined &&
                    values.includes(txn.categoryId))
            )
        }
        case 'tag': {
            const values = asStringList(condition.value)
            if (values.length === 0) return true
            const onTxn = evaluation.tagsByTransaction.get(txn.id)
            if (!onTxn) return false
            // One group per selected tag — the tag plus its descendants when
            // `includeSubtags` is on (native's `expandTagGroups`): `any` needs
            // a hit in some group, `all` a hit in every group.
            const hitsGroup = (id: string): boolean => {
                if (condition.includeSubtags === true) {
                    const group = evaluation.tagDescendants.get(id)
                    if (group) {
                        for (const member of group) {
                            if (onTxn.has(member)) return true
                        }
                        return false
                    }
                }
                return onTxn.has(id)
            }
            return condition.match === 'all'
                ? values.every(hitsGroup)
                : values.some(hitsGroup)
        }
        case 'currency': {
            const values = asStringList(condition.value)
            return values.length === 0 || values.includes(txn.currency)
        }
        case 'amount': {
            const range =
                typeof condition.value === 'object' && condition.value !== null
                    ? (condition.value as Record<string, unknown>)
                    : {}
            const amount = txn.amount < 0n ? -txn.amount : txn.amount
            if (
                typeof range.min === 'number' &&
                amount < BigInt(Math.round(range.min))
            ) {
                return false
            }
            if (
                typeof range.max === 'number' &&
                amount > BigInt(Math.round(range.max))
            ) {
                return false
            }
            return true
        }
        case 'text': {
            if (typeof condition.value !== 'string') return true
            const needle = condition.value.trim().toLowerCase()
            if (!needle) return true
            return (
                txn.name.toLowerCase().includes(needle) ||
                (txn.description ?? '').toLowerCase().includes(needle)
            )
        }
        default:
            // Forward-compatible: an unknown field written by a newer client
            // must not silently exclude every row.
            return true
    }
}

/**
 * Signed contribution of a transaction to net cash flow. Transfers are
 * excluded — they move money between the user's own accounts — matching
 * `SummaryRepository` on native.
 */
export function netCents(txn: Transaction): bigint {
    switch (txn.type) {
        case 'income':
            return txn.amount < 0n ? -txn.amount : txn.amount
        case 'expense':
            return -(txn.amount < 0n ? -txn.amount : txn.amount)
        case 'balance_adjustment':
            return txn.amount
        default:
            return 0n
    }
}

export function absCents(txn: Transaction): bigint {
    return txn.amount < 0n ? -txn.amount : txn.amount
}

/**
 * The whole evaluation pipeline for one stored filter config: parse, pre-resolve
 * tag membership, scan the anchored window. Every widget query starts here.
 */
export async function evaluateConfig(
    ctx: QueryCtx,
    userId: string,
    config: string,
    limit: number | null,
    asOfMs: bigint,
): Promise<MatchResult> {
    const { filter, root } = filterFromConfig(config)
    const evaluation = await buildEvaluationContext(
        ctx,
        userId,
        root,
        new Date(),
        asOfMs,
    )
    return collectMatching(ctx, userId, filter, root, evaluation, limit)
}
