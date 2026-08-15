import {
    collectTagConditions,
    type FilterCondition,
    type FilterGroup,
    type FilterNode,
    filterToCanonical,
    isFilterGroup,
    isSimplyRepresentable,
    parseFilterConfig,
    resolveDateWindow,
    type SimpleFilter,
} from '@wallet-bot/shared'
import type { Doc } from '../../_generated/dataModel'
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

export type Transaction = Doc<'transactions'>

export type EvaluationContext = {
    /** transactionId -> the tag ids on it, for the tag conditions in the tree. */
    tagsByTransaction: Map<string, Set<string>>
    now: Date
}

export function filterFromConfig(config: string | null | undefined): {
    filter: SimpleFilter
    root: FilterGroup
} {
    const filter = parseFilterConfig(config ?? '')
    return { filter, root: filterToCanonical(filter) }
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
): Promise<EvaluationContext> {
    const conditions = collectTagConditions(root)
    const tagsByTransaction = new Map<string, Set<string>>()
    if (conditions.length === 0) return { tagsByTransaction, now }

    const wanted = new Set<string>()
    for (const condition of conditions) {
        const ids = Array.isArray(condition.value)
            ? condition.value.filter(
                  (id): id is string => typeof id === 'string',
              )
            : []
        for (const id of ids) wanted.add(id)
    }
    if (wanted.size === 0) return { tagsByTransaction, now }

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
        const queue = [...wanted]
        while (queue.length > 0) {
            const current = queue.pop()
            if (current === undefined) break
            for (const child of childrenByParent.get(current) ?? []) {
                if (!wanted.has(child)) {
                    wanted.add(child)
                    queue.push(child)
                }
            }
        }
    }

    for (const tagId of wanted) {
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
    return { tagsByTransaction, now }
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
): Promise<Transaction[]> {
    const window = resolveDateWindow(filter, evaluation.now)
    const fromMs = window?.fromMs ?? null
    // The stored window is half-open; the index range is inclusive, so step
    // back one millisecond rather than widening the range by a day.
    const toMs =
        window?.toExclusiveMs === null || window?.toExclusiveMs === undefined
            ? null
            : window.toExclusiveMs - 1

    const anchorAccount =
        filter.accountIds.length === 1 &&
        filter.accountDirection !== 'destination'
            ? filter.accountIds[0]
            : null
    const anchorCategory =
        filter.categoryIds.length === 1 ? filter.categoryIds[0] : null

    const stream = anchorAccount
        ? ctx.db
              .query('transactions')
              .withIndex('by_user_account_date', (q) => {
                  const base = q
                      .eq('userId', userId)
                      .eq('accountId', anchorAccount)
                  if (fromMs !== null && toMs !== null) {
                      return base
                          .gte('date', BigInt(fromMs))
                          .lte('date', BigInt(toMs))
                  }
                  if (fromMs !== null) return base.gte('date', BigInt(fromMs))
                  if (toMs !== null) return base.lte('date', BigInt(toMs))
                  return base
              })
        : anchorCategory
          ? ctx.db
                .query('transactions')
                .withIndex('by_user_category_date', (q) => {
                    const base = q
                        .eq('userId', userId)
                        .eq('categoryId', anchorCategory)
                    if (fromMs !== null && toMs !== null) {
                        return base
                            .gte('date', BigInt(fromMs))
                            .lte('date', BigInt(toMs))
                    }
                    if (fromMs !== null) return base.gte('date', BigInt(fromMs))
                    if (toMs !== null) return base.lte('date', BigInt(toMs))
                    return base
                })
          : ctx.db.query('transactions').withIndex('by_user_date', (q) => {
                const base = q.eq('userId', userId)
                if (fromMs !== null && toMs !== null) {
                    return base
                        .gte('date', BigInt(fromMs))
                        .lte('date', BigInt(toMs))
                }
                if (fromMs !== null) return base.gte('date', BigInt(fromMs))
                if (toMs !== null) return base.lte('date', BigInt(toMs))
                return base
            })

    const matched: Transaction[] = []
    let scanned = 0
    for await (const txn of stream.order('desc')) {
        scanned++
        if (scanned > MAX_SCAN) break
        if (txn.isArchived) continue
        if (matchesNode(txn, root, evaluation)) {
            matched.push(txn)
            if (limit !== null && matched.length >= limit) break
        }
    }
    return matched
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
    const negate = condition.operator === 'not in'
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
        case 'date':
            // The date dimension is served by the index range, not the
            // predicate — see `collectMatching`.
            return true
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
            return condition.match === 'all'
                ? values.every((id) => onTxn.has(id))
                : values.some((id) => onTxn.has(id))
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

/** Whether a stored filter is still one the simple editor can render. */
export function isSimpleConfig(config: string): boolean {
    const { root } = filterFromConfig(config)
    return isSimplyRepresentable(root)
}
