// Server-side executor for the agent's tools.
//
// This is the third implementation of the same tool contract, and that is on
// purpose rather than an accident:
//
//   - `apps/native/lib/voice/tool_executors.dart` runs on the device against
//     the local Drift database, because native must work offline;
//   - the `v1/*` mutations serve the app's own forms, authenticated as the
//     signed-in user;
//   - this file serves an agent that has no session at all — a WhatsApp turn
//     acting for a `userId` the identity gate already proved.
//
// The contract they share is `packages/shared/src/tools/definitions.ts`, and
// every argument here is validated against those same zod schemas. What must
// not drift is the *money* semantics; where this file makes a choice the v1
// mutations make differently, it is called out inline.
//
// Authorization: `userId` is a trusted argument. This is an `internalMutation`,
// so it can only be called from another Convex function — never from a client —
// and its single caller resolves the user from the conversation's `userId`,
// which is only ever set by redeeming a link code minted in an authenticated
// session. Nothing here reads a client-supplied identity.

import {
    AGENT_CONTEXT_CAPS,
    adjustmentAmount,
    convertAmount,
    DEFAULT_FX_MARKET,
    fxAlternatives,
    isFxQuoteStale,
    isValidCurrencyCode,
    normalizeCurrencyCode,
    parseAmountToCents,
    pastCutoffBigInt,
    resolveFxQuote,
    runCalculate,
    runCalculateDate,
    type ToolArgs,
    toolSchemas,
} from '@wallet-bot/shared'
import { v } from 'convex/values'
import type { Doc } from '../_generated/dataModel'
import type { MutationCtx } from '../_generated/server'
import { internalMutation } from '../_generated/server'
import { readSnapshot } from '../exchangeRates/helpers'
import { resolveFlagsForUser } from '../featureFlags/helpers'
import { nextSeq, writeTombstone } from '../sync/helpers'
import { tagAggregateDetach } from '../tags/helpers'
import {
    recordFinancialAccountCreated,
    recordMovementCreated,
    recordTransferCreated,
} from '../telemetry/metrics'
import {
    aggregateInsert,
    aggregateReplace,
    balanceBeforeInLedger,
} from '../transactions/helpers'
import { hasDuplicateAccount } from '../v1/accounts/helpers'
import {
    DEFAULT_ACCOUNT_COLOR,
    DEFAULT_ACCOUNT_ICON,
} from '../v1/accounts/mutations'
import {
    DEFAULT_CATEGORY_COLOR,
    DEFAULT_CATEGORY_ICON,
} from '../v1/categories/mutations'
import { DEFAULT_TAG_COLOR } from '../v1/tags/mutations'
import { attachTags, detachTags } from '../v1/transactions/mutations'
import { computeAccountBalance } from '../v1/transactions/queries'
import { getDefaultCurrency } from '../v1/users/helpers'
import { newEntityId } from './idempotency'
import type { Resolution } from './resolve'
import { resolveAccount, resolveCategory, resolveTag } from './resolve'
import {
    formatLocalDateTime,
    hostDateAtLocalWallClock,
    parseAgentBalanceAsOf,
    parseAgentDate,
    parseAgentDateEndOfDay,
    parseAgentTransactionDate,
} from './time'
import {
    AGENT_CHANNEL_SKILLS,
    flagForTool,
    hasUnsupportedRecurrenceArguments,
    isAgentToolName,
} from './toolset'

// Every read below is narrowed to one user through an index, but a user with a
// long history could still ask for a year of transactions. These caps keep a
// single tool call inside a mutation's transaction budget. When a cap bites,
// the result says so — a truncated total the model reports as final would be a
// wrong number stated confidently, which is the worst failure this agent has.
const MAX_LIST_LIMIT = 50
const MAX_TAG_JOIN_SCAN = 500
const MAX_SUMMARY_ROWS = 2000

// Same ceiling `v1/memories/mutations.ts` enforces: memories are one-liners,
// not documents.
const MAX_MEMORY_CHARS = 500

type ToolResult = Record<string, unknown>

const ok = (data: ToolResult = {}): ToolResult => ({ ok: true, ...data })
const fail = (error: string, data: ToolResult = {}): ToolResult => ({
    ok: false,
    error,
    ...data,
})

const centsToDecimal = (cents: bigint): number => Number(cents) / 100

// Ambiguity is surfaced, not guessed at: the model is told the candidates so
// it can ask the user which one they meant.
const unresolved = <T>(
    label: string,
    resolution: Exclude<Resolution<T>, { kind: 'resolved' }>,
): ToolResult =>
    resolution.kind === 'ambiguous'
        ? fail(`${label} is ambiguous`, { candidates: resolution.candidates })
        : fail(`${label} not found`)

type Ctx = MutationCtx

type Clock = { nowMs: number; offsetMinutes: number }

// Identifies this specific write within its turn, so a replay reuses the same
// entity id instead of inserting a second row. Undefined for callers that
// cannot be replayed. See `agent/idempotency.ts`.
type WriteKey = string | undefined

const getTransactionRow = async (
    ctx: Ctx,
    userId: string,
    id: string,
): Promise<Doc<'transactions'> | null> =>
    await ctx.db
        .query('transactions')
        .withIndex('by_user_id', (q) => q.eq('userId', userId).eq('id', id))
        .unique()

const serializeTransaction = (
    t: Doc<'transactions'>,
    clock: Clock,
): ToolResult => ({
    id: t.id,
    type: t.type,
    name: t.name,
    description: t.description ?? null,
    date: Number(t.date),
    dateLocal: formatLocalDateTime(Number(t.date), clock.offsetMinutes),
    dateConfirmed: t.dateConfirmed,
    timeStatus: t.timeStatus ?? 'none',
    accountId: t.accountId,
    categoryId: t.categoryId,
    amount: centsToDecimal(t.amount),
    currency: t.currency,
    toAccountId: t.toAccountId ?? null,
    toAmount: t.toAmount !== undefined ? centsToDecimal(t.toAmount) : null,
    status: t.status,
    balanceAfter:
        t.balanceAfter !== undefined ? centsToDecimal(t.balanceAfter) : null,
    isArchived: t.isArchived,
})

// A supplied `date` is what makes the calendar day certain. The model also
// sends `dateConfirmed`, but the payload is the authority: a mistaken boolean
// must not mark a defaulted-today entry as confirmed. Same rule as the native
// executor.
const dateConfirmedOf = (date: string | undefined): boolean =>
    typeof date === 'string' && date.trim().length > 0

// Resolves the tag references on a create. Unresolvable names are skipped
// rather than failing the whole write — losing a tag is recoverable, losing
// the expense the user just reported is not. The names that did not resolve
// come back so the model can mention them.
const resolveTagIds = async (
    ctx: Ctx,
    userId: string,
    raw: string[] | undefined,
): Promise<{ ids: string[]; missing: string[] }> => {
    const ids: string[] = []
    const missing: string[] = []
    for (const item of raw ?? []) {
        const found = await resolveTag(ctx, userId, item)
        if (found.kind === 'resolved') ids.push(found.value.id)
        else missing.push(item)
    }
    return { ids, missing }
}

// ───── Accounts ─────

const listAccountsTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'listAccounts'>,
): Promise<ToolResult> => {
    const rows = args.includeArchived
        ? await ctx.db
              .query('accounts')
              .withIndex('by_user_seq', (q) => q.eq('userId', userId))
              .collect()
        : await ctx.db
              .query('accounts')
              .withIndex('by_user_archived', (q) =>
                  q.eq('userId', userId).eq('isArchived', false),
              )
              .collect()
    return ok({
        accounts: rows.map((a) => ({
            id: a.id,
            name: a.name,
            currency: a.currency,
            color: a.color,
            icon: a.icon,
            isArchived: a.isArchived,
        })),
    })
}

const createAccountTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'createAccount'>,
    writeKey: WriteKey,
): Promise<ToolResult> => {
    const name = args.name.trim()
    if (name.length === 0) return fail('Account name is required')
    const currency = args.currency ?? (await getDefaultCurrency(ctx, userId))
    if (await hasDuplicateAccount(ctx, userId, currency, name)) {
        return fail('An account with that name and currency already exists')
    }

    const id = await newEntityId(writeKey)
    const replay = await ctx.db
        .query('accounts')
        .withIndex('by_user_id', (q) => q.eq('userId', userId).eq('id', id))
        .unique()
    if (replay)
        return ok({
            id,
            name: replay.name,
            currency: replay.currency,
            duplicate: true,
        })

    const seq = await nextSeq(ctx, userId)
    const now = BigInt(Date.now())
    await ctx.db.insert('accounts', {
        userId,
        id,
        name,
        currency,
        description: args.description,
        color: args.color ?? DEFAULT_ACCOUNT_COLOR,
        icon: args.icon ?? DEFAULT_ACCOUNT_ICON,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        seq,
    })
    await recordFinancialAccountCreated(ctx, {
        userId,
        createdBy: 'agent',
        ingestPath: 'whatsapp',
    })
    return ok({ id, name, currency })
}

const updateAccountTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'updateAccount'>,
): Promise<ToolResult> => {
    const found = await resolveAccount(ctx, userId, args.idOrName)
    if (found.kind !== 'resolved') return unresolved('Account', found)
    const row = found.value

    // Currency is immutable and the tool schema has no currency field, so the
    // uniqueness check only ever moves the name within the same currency.
    if (args.name !== undefined) {
        const nextName = args.name.trim()
        if (nextName.length === 0) return fail('Account name cannot be empty')
        if (
            await hasDuplicateAccount(
                ctx,
                userId,
                row.currency,
                nextName,
                row._id,
            )
        ) {
            return fail('An account with that name and currency already exists')
        }
    }

    const seq = await nextSeq(ctx, userId)
    const patch: {
        name?: string
        description?: string
        color?: string
        icon?: string
    } = {}
    if (args.name !== undefined) patch.name = args.name.trim()
    if (args.description !== undefined) patch.description = args.description
    if (args.color !== undefined) patch.color = args.color
    if (args.icon !== undefined) patch.icon = args.icon
    await ctx.db.patch(row._id, {
        ...patch,
        updatedAt: BigInt(Date.now()),
        seq,
    })
    return ok({ id: row.id })
}

const archiveAccountTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'archiveAccount'>,
): Promise<ToolResult> => {
    const found = await resolveAccount(ctx, userId, args.idOrName)
    if (found.kind !== 'resolved') return unresolved('Account', found)
    const row = found.value

    const seq = await nextSeq(ctx, userId)
    await ctx.db.patch(row._id, {
        isArchived: true,
        updatedAt: BigInt(Date.now()),
        seq,
    })
    await writeTombstone(ctx, {
        userId,
        tableName: 'accounts',
        entityId: row.id,
        seq,
    })
    return ok({ id: row.id })
}

// ───── Categories ─────

const listCategoriesTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'listCategories'>,
): Promise<ToolResult> => {
    const rows = args.includeArchived
        ? await ctx.db
              .query('categories')
              .withIndex('by_user_seq', (q) => q.eq('userId', userId))
              .collect()
        : await ctx.db
              .query('categories')
              .withIndex('by_user_archived', (q) =>
                  q.eq('userId', userId).eq('isArchived', false),
              )
              .collect()
    return ok({
        categories: rows.map((c) => ({
            id: c.id,
            name: c.name,
            description: c.description ?? null,
            color: c.color,
            icon: c.icon,
            isArchived: c.isArchived,
        })),
    })
}

const createCategoryTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'createCategory'>,
    writeKey: WriteKey,
): Promise<ToolResult> => {
    const name = args.name.trim()
    if (name.length === 0) return fail('Category name is required')

    const id = await newEntityId(writeKey)
    const replay = await ctx.db
        .query('categories')
        .withIndex('by_user_id', (q) => q.eq('userId', userId).eq('id', id))
        .unique()
    if (replay) return ok({ id, name: replay.name, duplicate: true })

    const seq = await nextSeq(ctx, userId)
    const now = BigInt(Date.now())
    await ctx.db.insert('categories', {
        userId,
        id,
        name,
        description: args.description,
        color: args.color ?? DEFAULT_CATEGORY_COLOR,
        icon: args.icon ?? DEFAULT_CATEGORY_ICON,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        seq,
    })
    return ok({ id, name })
}

const updateCategoryTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'updateCategory'>,
): Promise<ToolResult> => {
    const found = await resolveCategory(ctx, userId, args.idOrName)
    if (found.kind !== 'resolved') return unresolved('Category', found)
    const row = found.value

    const seq = await nextSeq(ctx, userId)
    const patch: {
        name?: string
        description?: string
        color?: string
        icon?: string
    } = {}
    if (args.name !== undefined) {
        const nextName = args.name.trim()
        if (nextName.length === 0) return fail('Category name cannot be empty')
        patch.name = nextName
    }
    if (args.description !== undefined) patch.description = args.description
    if (args.color !== undefined) patch.color = args.color
    if (args.icon !== undefined) patch.icon = args.icon
    await ctx.db.patch(row._id, {
        ...patch,
        updatedAt: BigInt(Date.now()),
        seq,
    })
    return ok({ id: row.id })
}

const archiveCategoryTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'archiveCategory'>,
): Promise<ToolResult> => {
    const found = await resolveCategory(ctx, userId, args.idOrName)
    if (found.kind !== 'resolved') return unresolved('Category', found)
    const row = found.value

    const seq = await nextSeq(ctx, userId)
    await ctx.db.patch(row._id, {
        isArchived: true,
        updatedAt: BigInt(Date.now()),
        seq,
    })
    await writeTombstone(ctx, {
        userId,
        tableName: 'categories',
        entityId: row.id,
        seq,
    })
    return ok({ id: row.id })
}

// ───── Tags ─────

const listTagsTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'listTags'>,
): Promise<ToolResult> => {
    const rows = args.includeArchived
        ? await ctx.db
              .query('tags')
              .withIndex('by_user_seq', (q) => q.eq('userId', userId))
              .collect()
        : await ctx.db
              .query('tags')
              .withIndex('by_user_archived', (q) =>
                  q.eq('userId', userId).eq('isArchived', false),
              )
              .collect()
    return ok({
        tags: rows.map((t) => ({
            id: t.id,
            name: t.name,
            parentId: t.parentId ?? null,
            color: t.color,
            isArchived: t.isArchived,
        })),
    })
}

const createTagTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'createTag'>,
    writeKey: WriteKey,
): Promise<ToolResult> => {
    const name = args.name.trim()
    if (name.length === 0) return fail('Tag name is required')

    let parentId: string | undefined
    if (args.parentIdOrName !== undefined) {
        const parent = await resolveTag(ctx, userId, args.parentIdOrName)
        if (parent.kind !== 'resolved') return unresolved('Parent tag', parent)
        if (parent.value.isArchived) return fail('Parent tag not found')
        parentId = parent.value.id
    }

    const id = await newEntityId(writeKey)
    const replay = await ctx.db
        .query('tags')
        .withIndex('by_user_id', (q) => q.eq('userId', userId).eq('id', id))
        .unique()
    if (replay) return ok({ id, name: replay.name, duplicate: true })

    const seq = await nextSeq(ctx, userId)
    const now = BigInt(Date.now())
    await ctx.db.insert('tags', {
        userId,
        id,
        name,
        description: args.description,
        parentId,
        color: args.color ?? DEFAULT_TAG_COLOR,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        seq,
    })
    return ok({ id, name })
}

const updateTagTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'updateTag'>,
): Promise<ToolResult> => {
    const found = await resolveTag(ctx, userId, args.idOrName)
    if (found.kind !== 'resolved') return unresolved('Tag', found)
    const row = found.value

    // The tool schema has no way to say "clear the parent" (its
    // `parentIdOrName` is an optional string, not a nullable one), so an
    // absent argument means unchanged and the field is left alone rather than
    // patched with `undefined`.
    const patch: {
        name?: string
        description?: string
        color?: string
        parentId?: string
    } = {}
    if (args.parentIdOrName !== undefined) {
        const parent = await resolveTag(ctx, userId, args.parentIdOrName)
        if (parent.kind !== 'resolved') return unresolved('Parent tag', parent)
        if (parent.value.id === row.id) {
            return fail('A tag cannot be its own parent')
        }
        patch.parentId = parent.value.id
    }

    const seq = await nextSeq(ctx, userId)
    if (args.name !== undefined) {
        const nextName = args.name.trim()
        if (nextName.length === 0) return fail('Tag name cannot be empty')
        patch.name = nextName
    }
    if (args.description !== undefined) patch.description = args.description
    if (args.color !== undefined) patch.color = args.color
    const updatedAt = BigInt(Date.now())
    if (patch.parentId !== undefined && patch.parentId !== row.parentId) {
        // Moving under another parent drops the tag's position among its old
        // siblings. Written with `replace` and an explicit document, as below
        // and in `v1/tags/mutations.ts`, so the field is really gone.
        const { _id, _creationTime, position: _position, ...rest } = row
        await ctx.db.replace(_id, { ...rest, ...patch, updatedAt, seq })
        return ok({ id: row.id })
    }
    await ctx.db.patch(row._id, { ...patch, updatedAt, seq })
    return ok({ id: row.id })
}

const archiveTagTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'archiveTag'>,
): Promise<ToolResult> => {
    const found = await resolveTag(ctx, userId, args.idOrName)
    if (found.kind !== 'resolved') return unresolved('Tag', found)
    const row = found.value

    // Non-cascading, matching the native executor: direct children are
    // re-parented onto this tag's parent rather than disappearing with it.
    const children = await ctx.db
        .query('tags')
        .withIndex('by_user_parent', (q) =>
            q.eq('userId', userId).eq('parentId', row.id),
        )
        .collect()
    for (const child of children) {
        if (child.isArchived) continue
        const childSeq = await nextSeq(ctx, userId)
        // Written with `replace` and an explicitly built document, the same
        // way `v1/tags/mutations.ts` does it: a child of a top-level tag must
        // end up with no `parentId` field at all, and `patch(..., {parentId:
        // undefined})` is ambiguous about whether that removes it. `position`
        // is deliberately left out: it ranked the child among its old
        // siblings, and the child is changing parent.
        const doc: {
            userId: string
            id: string
            name: string
            color: string
            isArchived: boolean
            createdAt: bigint
            updatedAt: bigint
            seq: bigint
            description?: string
            parentId?: string
        } = {
            userId: child.userId,
            id: child.id,
            name: child.name,
            color: child.color,
            isArchived: child.isArchived,
            createdAt: child.createdAt,
            updatedAt: BigInt(Date.now()),
            seq: childSeq,
        }
        if (child.description !== undefined) doc.description = child.description
        if (row.parentId !== undefined) doc.parentId = row.parentId
        await ctx.db.replace(child._id, doc)
    }

    const seq = await nextSeq(ctx, userId)
    await ctx.db.patch(row._id, {
        isArchived: true,
        updatedAt: BigInt(Date.now()),
        seq,
    })
    await writeTombstone(ctx, {
        userId,
        tableName: 'tags',
        entityId: row.id,
        seq,
    })
    return ok({ id: row.id })
}

// ───── Transaction reads ─────

const listTransactionsTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'listTransactions'>,
    clock: Clock,
): Promise<ToolResult> => {
    // With no filters this is the "what did I spend lately" shortcut that used
    // to be its own `getRecentTransactions` tool, so it defaults to a chat-sized
    // ten rows; a filtered query is a deliberate search and defaults wider.
    const filtered =
        args.type !== undefined ||
        args.status !== undefined ||
        args.accountIdOrName !== undefined ||
        args.categoryIdOrName !== undefined ||
        args.tagIdOrName !== undefined ||
        args.dateFrom !== undefined ||
        args.dateTo !== undefined
    const limit = Math.min(
        Math.max(args.limit ?? (filtered ? 50 : 10), 1),
        MAX_LIST_LIMIT,
    )

    let accountId: string | undefined
    if (args.accountIdOrName !== undefined) {
        const found = await resolveAccount(ctx, userId, args.accountIdOrName)
        if (found.kind !== 'resolved') return unresolved('Account', found)
        accountId = found.value.id
    }
    let categoryId: string | undefined
    if (args.categoryIdOrName !== undefined) {
        const found = await resolveCategory(ctx, userId, args.categoryIdOrName)
        if (found.kind !== 'resolved') return unresolved('Category', found)
        categoryId = found.value.id
    }
    let tagId: string | undefined
    if (args.tagIdOrName !== undefined) {
        const found = await resolveTag(ctx, userId, args.tagIdOrName)
        if (found.kind !== 'resolved') return unresolved('Tag', found)
        tagId = found.value.id
    }

    const from =
        args.dateFrom !== undefined
            ? BigInt(
                  parseAgentDate(
                      args.dateFrom,
                      clock.nowMs,
                      clock.offsetMinutes,
                  ),
              )
            : undefined
    const cutoff = pastCutoffBigInt(new Date(clock.nowMs))
    // Respect the requested day while excluding occurrences that are not due.
    const requestedTo =
        args.dateTo !== undefined
            ? BigInt(
                  parseAgentDateEndOfDay(
                      args.dateTo,
                      clock.nowMs,
                      clock.offsetMinutes,
                  ),
              )
            : undefined
    const to =
        requestedTo !== undefined && requestedTo < cutoff
            ? requestedTo
            : cutoff - 1n

    const matches = (t: Doc<'transactions'>): boolean => {
        if (t.isArchived) return false
        if (args.type !== undefined && t.type !== args.type) return false
        if (args.status !== undefined && t.status !== args.status) return false
        if (categoryId !== undefined && t.categoryId !== categoryId)
            return false
        if (accountId !== undefined && t.accountId !== accountId) return false
        if (from !== undefined && t.date < from) return false
        if (to !== undefined && t.date > to) return false
        return true
    }

    // A tag filter is driven from the join table: it is far narrower than any
    // date range, and there is no index that combines the two.
    if (tagId !== undefined) {
        const joins = await ctx.db
            .query('transactionTags')
            .withIndex('by_user_tag', (q) =>
                q.eq('userId', userId).eq('tagId', tagId),
            )
            .take(MAX_TAG_JOIN_SCAN)
        const found: Doc<'transactions'>[] = []
        for (const join of joins) {
            const txn = await getTransactionRow(ctx, userId, join.transactionId)
            if (txn && matches(txn)) found.push(txn)
        }
        found.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0))
        return ok({
            items: found
                .slice(0, limit)
                .map((t) => serializeTransaction(t, clock)),
            truncated: joins.length === MAX_TAG_JOIN_SCAN,
        })
    }

    // Otherwise pick the narrowest index the filters allow, and put the date
    // range inside it so the scan never leaves the window.
    const rows =
        accountId !== undefined
            ? await ctx.db
                  .query('transactions')
                  .withIndex('by_user_account_date', (q) => {
                      const base = q
                          .eq('userId', userId)
                          .eq('accountId', accountId)
                      if (from !== undefined && to !== undefined)
                          return base.gte('date', from).lte('date', to)
                      if (from !== undefined) return base.gte('date', from)
                      if (to !== undefined) return base.lte('date', to)
                      return base
                  })
                  .order('desc')
                  .take(MAX_SUMMARY_ROWS)
            : categoryId !== undefined
              ? await ctx.db
                    .query('transactions')
                    .withIndex('by_user_category_date', (q) => {
                        const base = q
                            .eq('userId', userId)
                            .eq('categoryId', categoryId)
                        if (from !== undefined && to !== undefined)
                            return base.gte('date', from).lte('date', to)
                        if (from !== undefined) return base.gte('date', from)
                        if (to !== undefined) return base.lte('date', to)
                        return base
                    })
                    .order('desc')
                    .take(MAX_SUMMARY_ROWS)
              : await ctx.db
                    .query('transactions')
                    .withIndex('by_user_date', (q) => {
                        const base = q.eq('userId', userId)
                        if (from !== undefined && to !== undefined)
                            return base.gte('date', from).lte('date', to)
                        if (from !== undefined) return base.gte('date', from)
                        if (to !== undefined) return base.lte('date', to)
                        return base
                    })
                    .order('desc')
                    .take(MAX_SUMMARY_ROWS)

    const items = rows.filter(matches).slice(0, limit)
    return ok({
        items: items.map((t) => serializeTransaction(t, clock)),
        truncated: rows.length === MAX_SUMMARY_ROWS && items.length < limit,
    })
}

const getTransactionTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'getTransaction'>,
    clock: Clock,
): Promise<ToolResult> => {
    const txn = await getTransactionRow(ctx, userId, args.id)
    if (!txn) return fail('Transaction not found')
    const joins = await ctx.db
        .query('transactionTags')
        .withIndex('by_user_transaction', (q) =>
            q.eq('userId', userId).eq('transactionId', txn.id),
        )
        .collect()
    return ok({
        transaction: {
            ...serializeTransaction(txn, clock),
            tagIds: joins.map((j) => j.tagId),
        },
    })
}

// ───── Transaction writes ─────

type MovementArgs = ToolArgs<'addExpense'> | ToolArgs<'addIncome'>

const createMovement = async (
    ctx: Ctx,
    userId: string,
    type: 'expense' | 'income',
    args: MovementArgs,
    clock: Clock,
    writeKey: WriteKey,
): Promise<ToolResult> => {
    const account = await resolveAccount(ctx, userId, args.accountIdOrName)
    if (account.kind !== 'resolved') return unresolved('Account', account)
    const category = await resolveCategory(ctx, userId, args.categoryIdOrName)
    if (category.kind !== 'resolved') return unresolved('Category', category)

    const amount = parseAmountToCents(args.amount)
    if (amount <= 0n) return fail('Amount must be greater than 0')

    const date = BigInt(
        parseAgentTransactionDate(
            args.date,
            args.timeStatus,
            args.time,
            clock.nowMs,
            clock.offsetMinutes,
        ),
    )

    const id = await newEntityId(writeKey)
    const replay = await getTransactionRow(ctx, userId, id)
    if (replay) return ok({ id, duplicate: true })

    const seq = await nextSeq(ctx, userId)
    const now = BigInt(Date.now())
    const inserted = await ctx.db.insert('transactions', {
        userId,
        id,
        type,
        name: args.name,
        description: args.description,
        status: args.status ?? 'cleared',
        date,
        dateConfirmed: dateConfirmedOf(args.date),
        timeStatus: args.timeStatus,
        accountId: account.value.id,
        categoryId: category.value.id,
        amount,
        currency: account.value.currency,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        seq,
    })
    await aggregateInsert(ctx, inserted)

    const tags = await resolveTagIds(ctx, userId, args.tagIdsOrNames)
    if (tags.ids.length > 0) await attachTags(ctx, userId, id, tags.ids)

    await recordMovementCreated(ctx, {
        userId,
        movementType: type,
        createdBy: 'agent',
        ingestPath: 'whatsapp',
    })
    return ok({
        id,
        accountName: account.value.name,
        categoryName: category.value.name,
        currency: account.value.currency,
        date: Number(date),
        dateLocal: formatLocalDateTime(Number(date), clock.offsetMinutes),
        timeStatus: args.timeStatus,
        missingTags: tags.missing,
    })
}

const addTransferTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'addTransfer'>,
    clock: Clock,
    writeKey: WriteKey,
): Promise<ToolResult> => {
    const from = await resolveAccount(ctx, userId, args.fromAccountIdOrName)
    if (from.kind !== 'resolved') return unresolved('Source account', from)
    const to = await resolveAccount(ctx, userId, args.toAccountIdOrName)
    if (to.kind !== 'resolved') return unresolved('Destination account', to)
    if (from.value.id === to.value.id) {
        return fail('Source and destination accounts must differ')
    }

    // Unlike `v1/transactions/mutations.ts:createTransfer`, a category is
    // optional here. That mirrors the native executor, which stores `''` — a
    // transfer between two of your own accounts is not spending, and forcing
    // the agent to invent a category would put junk in the user's list.
    let categoryId = ''
    if (args.categoryIdOrName !== undefined) {
        const category = await resolveCategory(
            ctx,
            userId,
            args.categoryIdOrName,
        )
        if (category.kind !== 'resolved')
            return unresolved('Category', category)
        categoryId = category.value.id
    }

    const amount = parseAmountToCents(args.amount)
    if (amount <= 0n) return fail('Amount must be greater than 0')

    const sameCurrency = from.value.currency === to.value.currency
    const toAmount =
        args.toAmount !== undefined
            ? parseAmountToCents(args.toAmount)
            : sameCurrency
              ? amount
              : args.exchangeRate !== undefined
                ? parseAmountToCents(args.amount * args.exchangeRate)
                : undefined
    if (toAmount === undefined) {
        return fail(
            'Cross-currency transfers require toAmount (or exchangeRate to derive it)',
        )
    }
    if (toAmount <= 0n) return fail('Destination amount must be greater than 0')

    const date = BigInt(
        parseAgentTransactionDate(
            args.date,
            args.timeStatus,
            args.time,
            clock.nowMs,
            clock.offsetMinutes,
        ),
    )

    const id = await newEntityId(writeKey)
    const replay = await getTransactionRow(ctx, userId, id)
    if (replay) return ok({ id, duplicate: true })

    const seq = await nextSeq(ctx, userId)
    const now = BigInt(Date.now())
    const inserted = await ctx.db.insert('transactions', {
        userId,
        id,
        type: 'transfer',
        name: args.name,
        description: args.description,
        status: 'cleared',
        date,
        dateConfirmed: dateConfirmedOf(args.date),
        timeStatus: args.timeStatus,
        accountId: from.value.id,
        categoryId,
        amount,
        currency: from.value.currency,
        toAccountId: to.value.id,
        toAmount,
        toCurrency: to.value.currency,
        exchangeRate: sameCurrency
            ? undefined
            : Number(toAmount) / Number(amount),
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        seq,
    })
    await aggregateInsert(ctx, inserted)

    const tags = await resolveTagIds(ctx, userId, args.tagIdsOrNames)
    if (tags.ids.length > 0) await attachTags(ctx, userId, id, tags.ids)

    await recordTransferCreated(ctx, {
        userId,
        createdBy: 'agent',
        ingestPath: 'whatsapp',
        crossCurrency: !sameCurrency,
    })
    return ok({
        id,
        fromAccountName: from.value.name,
        toAccountName: to.value.name,
        amount: centsToDecimal(amount),
        toAmount: centsToDecimal(toAmount),
        date: Number(date),
        dateLocal: formatLocalDateTime(Number(date), clock.offsetMinutes),
        missingTags: tags.missing,
    })
}

const addBalanceAdjustmentTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'addBalanceAdjustment'>,
    clock: Clock,
    writeKey: WriteKey,
): Promise<ToolResult> => {
    const account = await resolveAccount(ctx, userId, args.accountIdOrName)
    if (account.kind !== 'resolved') return unresolved('Account', account)

    // Checked before the balance is read, not just before the insert. On a
    // replay the first adjustment is already in the ledger, so the balance
    // here would come back as the already-adjusted one and the delta would be
    // zero — a second, pointless adjustment row rather than a no-op.
    const id = await newEntityId(writeKey)
    const replay = await getTransactionRow(ctx, userId, id)
    if (replay) return ok({ id, duplicate: true })

    const date = BigInt(
        parseAgentTransactionDate(
            args.date,
            args.timeStatus,
            args.time,
            clock.nowMs,
            clock.offsetMinutes,
        ),
    )
    const now = BigInt(Date.now())

    // `balanceAfter` is the user's declaration and is stored verbatim; the
    // delta is derived from the ledger just before the adjustment's own date,
    // never the other way around, and later writes before it re-derive it.
    const balanceAfter = parseAmountToCents(args.balanceAfter)
    const current = await balanceBeforeInLedger(ctx, userId, account.value.id, {
        id,
        type: 'balance_adjustment',
        accountId: account.value.id,
        amount: 0n,
        balanceAfter,
        date,
        createdAt: now,
        isArchived: false,
    })
    const amount = adjustmentAmount(balanceAfter, current)

    const seq = await nextSeq(ctx, userId)
    const inserted = await ctx.db.insert('transactions', {
        userId,
        id,
        type: 'balance_adjustment',
        name: args.name ?? 'Ajuste de saldo',
        description: args.description,
        status: 'cleared',
        date,
        dateConfirmed: dateConfirmedOf(args.date),
        timeStatus: args.timeStatus,
        accountId: account.value.id,
        categoryId: '',
        amount,
        currency: account.value.currency,
        balanceAfter,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        seq,
    })
    await aggregateInsert(ctx, inserted)
    await recordMovementCreated(ctx, {
        userId,
        movementType: 'balance_adjustment',
        createdBy: 'agent',
        ingestPath: 'whatsapp',
    })
    return ok({
        id,
        accountName: account.value.name,
        previousBalance: centsToDecimal(current),
        balanceAfter: centsToDecimal(balanceAfter),
        difference: centsToDecimal(amount),
        currency: account.value.currency,
    })
}

const updateTransactionTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'updateTransaction'>,
    clock: Clock,
): Promise<ToolResult> => {
    const row = await getTransactionRow(ctx, userId, args.id)
    if (!row) return fail('Transaction not found')

    // An adjustment's amount is derived from the ledger and its date is when
    // the declaration was made; neither is editable. A new declaration is a
    // new adjustment.
    if (row.type === 'balance_adjustment') {
        if (args.amount !== undefined) {
            return fail(
                'A balance adjustment amount cannot be changed; record a new balance adjustment instead',
            )
        }
        if (
            args.date !== undefined ||
            args.time !== undefined ||
            args.timeStatus !== undefined
        ) {
            return fail('A balance adjustment date cannot be changed')
        }
    }

    let categoryId: string | undefined
    if (args.categoryIdOrName !== undefined) {
        const category = await resolveCategory(
            ctx,
            userId,
            args.categoryIdOrName,
        )
        if (category.kind !== 'resolved')
            return unresolved('Category', category)
        categoryId = category.value.id
    }

    const patch: {
        name?: string
        description?: string
        categoryId?: string
        status?: 'pending' | 'cleared'
        amount?: bigint
        toAmount?: bigint
        date?: bigint
        dateConfirmed?: boolean
        timeStatus?: 'confirmed' | 'approximation' | 'none'
    } = {}
    if (args.name !== undefined) patch.name = args.name
    if (args.description !== undefined) patch.description = args.description
    if (categoryId !== undefined) patch.categoryId = categoryId
    if (args.status !== undefined) patch.status = args.status
    if (args.amount !== undefined) {
        const amount = parseAmountToCents(args.amount)
        if (amount <= 0n) return fail('Amount must be greater than 0')
        patch.amount = amount
        // Same-currency transfers move the same money on both sides; letting
        // them diverge would silently break the destination balance.
        if (row.type === 'transfer' && row.toCurrency === row.currency) {
            patch.toAmount = amount
        }
    }
    if (args.date !== undefined || args.time !== undefined) {
        // Preserve the existing status when the model only moved the day.
        const timeStatus = args.timeStatus ?? row.timeStatus ?? 'none'
        patch.date = BigInt(
            parseAgentTransactionDate(
                args.date,
                timeStatus,
                args.time,
                clock.nowMs,
                clock.offsetMinutes,
            ),
        )
        patch.timeStatus = timeStatus
        if (args.date !== undefined) patch.dateConfirmed = true
    } else if (args.timeStatus !== undefined) {
        if (args.timeStatus !== 'none') {
            return fail(
                `date or time is required when timeStatus is ${args.timeStatus}`,
            )
        }
        patch.timeStatus = args.timeStatus
    }

    const seq = await nextSeq(ctx, userId)
    await ctx.db.patch(row._id, {
        ...patch,
        updatedAt: BigInt(Date.now()),
        seq,
    })
    await aggregateReplace(ctx, row, row._id)

    // Tags ride along with the rest of the edit, in the same transaction, so a
    // half-applied update is not a state this can end in.
    const missing: string[] = []
    let added = 0
    let removed = 0
    if (args.addTagIdsOrNames !== undefined) {
        const tags = await resolveTagIds(ctx, userId, args.addTagIdsOrNames)
        missing.push(...tags.missing)
        added = await attachTags(ctx, userId, row.id, tags.ids)
    }
    if (args.removeTagIdsOrNames !== undefined) {
        const tags = await resolveTagIds(ctx, userId, args.removeTagIdsOrNames)
        missing.push(...tags.missing)
        removed = await detachTags(ctx, userId, row.id, tags.ids)
    }

    const updated = await ctx.db.get(row._id)
    return ok({
        id: row.id,
        transaction: updated ? serializeTransaction(updated, clock) : null,
        ...(added > 0 ? { added } : {}),
        ...(removed > 0 ? { removed } : {}),
        ...(missing.length > 0 ? { missing } : {}),
    })
}

// Archives rather than hard-deletes, matching `v1/transactions/mutations.ts`:
// the row has to survive as a tombstone or syncing devices would never learn
// it is gone.
const deleteTransactionTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'deleteTransaction'>,
): Promise<ToolResult> => {
    const row = await getTransactionRow(ctx, userId, args.id)
    // Idempotent: deleting something already gone is a success, not an error.
    if (!row) return ok({ id: args.id })

    const joins = await ctx.db
        .query('transactionTags')
        .withIndex('by_user_transaction', (q) =>
            q.eq('userId', userId).eq('transactionId', args.id),
        )
        .collect()
    for (const join of joins) {
        const joinSeq = await nextSeq(ctx, userId)
        await tagAggregateDetach(ctx, join, row)
        await ctx.db.delete(join._id)
        await writeTombstone(ctx, {
            userId,
            tableName: 'transactionTags',
            entityId: join.id,
            seq: joinSeq,
        })
    }

    const seq = await nextSeq(ctx, userId)
    await ctx.db.patch(row._id, {
        isArchived: true,
        updatedAt: BigInt(Date.now()),
        seq,
    })
    await aggregateReplace(ctx, row, row._id)
    await writeTombstone(ctx, {
        userId,
        tableName: 'transactions',
        entityId: args.id,
        seq,
    })
    return ok({ id: args.id })
}

// ───── Summaries ─────

const summaryWindow = (
    dateFrom: string,
    dateTo: string,
    clock: Clock,
): { from: bigint; to: bigint } => ({
    from: BigInt(parseAgentDate(dateFrom, clock.nowMs, clock.offsetMinutes)),
    to: BigInt(
        parseAgentDateEndOfDay(dateTo, clock.nowMs, clock.offsetMinutes),
    ),
})

const summarizeTransactionsTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'summarizeTransactions'>,
    clock: Clock,
): Promise<ToolResult> => {
    const { from, to: requestedTo } = summaryWindow(
        args.dateFrom,
        args.dateTo,
        clock,
    )
    const cutoff = pastCutoffBigInt(new Date(clock.nowMs))
    const to = requestedTo < cutoff ? requestedTo : cutoff - 1n
    const rows = await ctx.db
        .query('transactions')
        .withIndex('by_user_date', (q) =>
            q.eq('userId', userId).gte('date', from).lte('date', to),
        )
        .take(MAX_SUMMARY_ROWS)
    const truncated = rows.length === MAX_SUMMARY_ROWS

    if (args.groupBy === 'category') {
        const totals = new Map<string, bigint>()
        for (const t of rows) {
            if (t.isArchived) continue
            // Transfers move money between the user's own accounts; counting
            // them as spend would double the totals.
            if (t.type === 'transfer') continue
            if (args.type !== undefined && t.type !== args.type) continue
            if (args.currency !== undefined && t.currency !== args.currency)
                continue
            totals.set(
                t.categoryId,
                (totals.get(t.categoryId) ?? 0n) + t.amount,
            )
        }

        const categories = await ctx.db
            .query('categories')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .collect()
        const nameById = new Map(categories.map((c) => [c.id, c.name]))

        return ok({
            groupBy: 'category',
            rows: [...totals.entries()]
                .map(([categoryId, cents]) => ({
                    categoryId,
                    name: nameById.get(categoryId) ?? '(unknown)',
                    total: centsToDecimal(cents),
                }))
                .sort((a, b) => Math.abs(b.total) - Math.abs(a.total)),
            truncated,
        })
    }

    const accounts = await ctx.db
        .query('accounts')
        .withIndex('by_user_archived', (q) =>
            q.eq('userId', userId).eq('isArchived', false),
        )
        .collect()
    const flows = new Map<
        string,
        { name: string; currency: string; inCents: bigint; outCents: bigint }
    >(
        accounts.map((a) => [
            a.id,
            { name: a.name, currency: a.currency, inCents: 0n, outCents: 0n },
        ]),
    )

    for (const t of rows) {
        if (t.isArchived) continue
        const source = flows.get(t.accountId)
        if (source) {
            if (t.type === 'expense' || t.type === 'transfer') {
                source.outCents += t.amount
            } else if (t.type === 'income') {
                source.inCents += t.amount
            } else if (t.amount >= 0n) {
                source.inCents += t.amount
            } else {
                source.outCents += -t.amount
            }
        }
        if (t.type === 'transfer' && t.toAccountId !== undefined) {
            const destination = flows.get(t.toAccountId)
            if (destination) {
                destination.inCents += t.toAmount ?? t.amount
            }
        }
    }

    return ok({
        groupBy: 'account',
        rows: [...flows.entries()].map(([accountId, flow]) => ({
            accountId,
            name: flow.name,
            currency: flow.currency,
            in: centsToDecimal(flow.inCents),
            out: centsToDecimal(flow.outCents),
            net: centsToDecimal(flow.inCents - flow.outCents),
        })),
        truncated,
    })
}

// ───── Memory ─────
//
// The same `agentMemories` rows the voice agent reads and writes through
// `v1/memories/*`, and the same rules: capped set, soft delete plus tombstone
// so every device learns the memory is gone. A memory saved over WhatsApp
// shows up in the next voice session, which is the whole point of storing it
// on the server rather than per channel.

const listMemories = async (ctx: Ctx, userId: string) =>
    await ctx.db
        .query('agentMemories')
        .withIndex('by_user_archived', (q) =>
            q.eq('userId', userId).eq('isArchived', false),
        )
        .take(AGENT_CONTEXT_CAPS.memories)

const memoryContent = (raw: string): string | null => {
    const content = raw.trim()
    if (!content) return null
    return content.length > MAX_MEMORY_CHARS
        ? content.slice(0, MAX_MEMORY_CHARS)
        : content
}

const getMemoryRow = async (ctx: Ctx, userId: string, id: string) =>
    await ctx.db
        .query('agentMemories')
        .withIndex('by_user_id', (q) => q.eq('userId', userId).eq('id', id))
        .unique()

const addMemoryTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'addMemory'>,
    writeKey: WriteKey,
): Promise<ToolResult> => {
    const content = memoryContent(args.content)
    if (content === null) return fail('Memory content cannot be empty')

    const id = await newEntityId(writeKey)
    const existing = await getMemoryRow(ctx, userId, id)
    // A replayed turn rebuilds the same id, so the memory is already there.
    if (existing) return ok({ id, duplicate: true })

    const active = await listMemories(ctx, userId)
    if (active.length >= AGENT_CONTEXT_CAPS.memories) {
        return fail(
            'Memory limit reached — consolidate first: merge or rewrite existing memories (updateMemory) and delete obsolete ones (forgetMemory) before adding new ones',
        )
    }

    const seq = await nextSeq(ctx, userId)
    const now = BigInt(Date.now())
    await ctx.db.insert('agentMemories', {
        userId,
        id,
        content,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        seq,
    })
    return ok({ id, content })
}

const updateMemoryTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'updateMemory'>,
): Promise<ToolResult> => {
    const content = memoryContent(args.content)
    if (content === null) return fail('Memory content cannot be empty')

    const row = await getMemoryRow(ctx, userId, args.id)
    if (!row || row.isArchived) return fail('Memory not found')

    const seq = await nextSeq(ctx, userId)
    await ctx.db.patch(row._id, {
        content,
        updatedAt: BigInt(Date.now()),
        seq,
    })
    return ok({ id: args.id, content })
}

const forgetMemoryTool = async (
    ctx: Ctx,
    userId: string,
    args: ToolArgs<'forgetMemory'>,
): Promise<ToolResult> => {
    const row = await getMemoryRow(ctx, userId, args.id)
    // Idempotent: forgetting something already gone is what the user wanted.
    if (!row || row.isArchived) return ok({ id: args.id })

    const seq = await nextSeq(ctx, userId)
    await ctx.db.patch(row._id, {
        isArchived: true,
        updatedAt: BigInt(Date.now()),
        seq,
    })
    await writeTombstone(ctx, {
        userId,
        tableName: 'agentMemories',
        entityId: args.id,
        seq,
    })
    return ok({ id: args.id })
}

// ───── Exchange rates ─────

const getExchangeRateTool = async (
    ctx: Ctx,
    args: ToolArgs<'getExchangeRate'>,
    clock: Clock,
): Promise<ToolResult> => {
    const from = normalizeCurrencyCode(args.from)
    const to = normalizeCurrencyCode(args.to)
    if (!isValidCurrencyCode(from))
        return fail(`Unknown currency code: ${from}`)
    if (!isValidCurrencyCode(to)) return fail(`Unknown currency code: ${to}`)
    if (from === to) return fail('from and to are the same currency')

    const snapshot = await readSnapshot(ctx)
    if (snapshot.length === 0) {
        return fail('Exchange rates are unavailable right now')
    }
    const resolution = resolveFxQuote(
        snapshot,
        from,
        to,
        args.market ?? DEFAULT_FX_MARKET,
    )
    if (!resolution) return fail(`No exchange rate available for ${from}→${to}`)

    const alternatives = fxAlternatives(snapshot, from, to)
    return ok({
        from: resolution.from,
        to: resolution.to,
        market: resolution.market,
        rate: resolution.rate,
        ...(resolution.buy === undefined ? {} : { buy: resolution.buy }),
        ...(resolution.sell === undefined ? {} : { sell: resolution.sell }),
        source: resolution.source,
        asOf: resolution.asOf,
        path: resolution.path,
        ...(isFxQuoteStale(resolution.asOf, clock.nowMs)
            ? { stale: true }
            : {}),
        ...(args.amount === undefined
            ? {}
            : { converted: convertAmount(args.amount, resolution.rate) }),
        ...(Object.keys(alternatives).length > 0 ? { alternatives } : {}),
    })
}

// ───── Math, dates and skills ─────
//
// Pure: no database, no user data, identical answers to the ones the native
// and web executors give for the same arguments. They are here so the model
// stops doing mental arithmetic in a channel where a wrong total reads exactly
// like a right one.

const calculateTool = (args: ToolArgs<'calculate'>): ToolResult => {
    try {
        const steps = runCalculate(args.steps)
        return ok({ steps, result: steps[steps.length - 1].value })
    } catch (error) {
        return fail(error instanceof Error ? error.message : String(error))
    }
}

const calculateDateTool = (
    args: ToolArgs<'calculateDate'>,
    clock: Clock,
): ToolResult => {
    try {
        // `runCalculateDate` reads the calendar off a Date's LOCAL fields,
        // which on the clients is the user's own zone and here is the server's.
        // Hand it an instant whose local fields spell out the user's wall
        // clock, so "hoy" means their today and not the deployment's.
        return ok({
            ...runCalculateDate(
                args,
                hostDateAtLocalWallClock(clock.nowMs, clock.offsetMinutes),
            ),
        })
    } catch (error) {
        return fail(error instanceof Error ? error.message : String(error))
    }
}

const readSkillTool = (args: ToolArgs<'readSkill'>): ToolResult => {
    const skill = AGENT_CHANNEL_SKILLS.find((skill) => skill.slug === args.slug)
    if (!skill) {
        return fail(`Unknown skill: ${args.slug}`, {
            availableSlugs: AGENT_CHANNEL_SKILLS.map((s) => s.slug),
        })
    }
    return ok({ slug: skill.slug, title: skill.title, body: skill.body })
}

// ───── Dispatch ─────

const dispatch = async (
    ctx: Ctx,
    userId: string,
    name: string,
    raw: unknown,
    clock: Clock,
    writeKey: WriteKey,
): Promise<ToolResult> => {
    switch (name) {
        case 'listAccounts':
            return await listAccountsTool(
                ctx,
                userId,
                toolSchemas.listAccounts.parse(raw),
            )
        case 'getAccount': {
            const args = toolSchemas.getAccount.parse(raw)
            const found = await resolveAccount(ctx, userId, args.idOrName)
            if (found.kind !== 'resolved') return unresolved('Account', found)
            return ok({
                account: {
                    id: found.value.id,
                    name: found.value.name,
                    currency: found.value.currency,
                    color: found.value.color,
                    icon: found.value.icon,
                    isArchived: found.value.isArchived,
                },
            })
        }
        case 'getAccountBalance': {
            const args = toolSchemas.getAccountBalance.parse(raw)
            const found = await resolveAccount(ctx, userId, args.idOrName)
            if (found.kind !== 'resolved') return unresolved('Account', found)
            // With a date, the balance at the end of that day in the user's
            // calendar; without one, the balance right now.
            const asOfMs =
                args.date === undefined
                    ? pastCutoffBigInt(new Date(clock.nowMs))
                    : parseAgentBalanceAsOf(
                          args.date,
                          clock.nowMs,
                          clock.offsetMinutes,
                      )
            const balance = await computeAccountBalance(
                ctx,
                userId,
                found.value.id,
                asOfMs,
            )
            return ok({
                accountId: found.value.id,
                accountName: found.value.name,
                balance: centsToDecimal(balance),
                currency: found.value.currency,
                ...(args.date !== undefined ? { date: args.date } : {}),
            })
        }
        case 'createAccount':
            return await createAccountTool(
                ctx,
                userId,
                toolSchemas.createAccount.parse(raw),
                writeKey,
            )
        case 'updateAccount':
            return await updateAccountTool(
                ctx,
                userId,
                toolSchemas.updateAccount.parse(raw),
            )
        case 'archiveAccount':
            return await archiveAccountTool(
                ctx,
                userId,
                toolSchemas.archiveAccount.parse(raw),
            )

        case 'listCategories':
            return await listCategoriesTool(
                ctx,
                userId,
                toolSchemas.listCategories.parse(raw),
            )
        case 'getCategory': {
            const args = toolSchemas.getCategory.parse(raw)
            const found = await resolveCategory(ctx, userId, args.idOrName)
            if (found.kind !== 'resolved') return unresolved('Category', found)
            return ok({
                category: {
                    id: found.value.id,
                    name: found.value.name,
                    description: found.value.description ?? null,
                    color: found.value.color,
                    icon: found.value.icon,
                },
            })
        }
        case 'createCategory':
            return await createCategoryTool(
                ctx,
                userId,
                toolSchemas.createCategory.parse(raw),
                writeKey,
            )
        case 'updateCategory':
            return await updateCategoryTool(
                ctx,
                userId,
                toolSchemas.updateCategory.parse(raw),
            )
        case 'archiveCategory':
            return await archiveCategoryTool(
                ctx,
                userId,
                toolSchemas.archiveCategory.parse(raw),
            )

        case 'listTags':
            return await listTagsTool(
                ctx,
                userId,
                toolSchemas.listTags.parse(raw),
            )
        case 'getTag': {
            const args = toolSchemas.getTag.parse(raw)
            const found = await resolveTag(ctx, userId, args.idOrName)
            if (found.kind !== 'resolved') return unresolved('Tag', found)
            return ok({
                tag: {
                    id: found.value.id,
                    name: found.value.name,
                    parentId: found.value.parentId ?? null,
                    color: found.value.color,
                },
            })
        }
        case 'createTag':
            return await createTagTool(
                ctx,
                userId,
                toolSchemas.createTag.parse(raw),
                writeKey,
            )
        case 'updateTag':
            return await updateTagTool(
                ctx,
                userId,
                toolSchemas.updateTag.parse(raw),
            )
        case 'archiveTag':
            return await archiveTagTool(
                ctx,
                userId,
                toolSchemas.archiveTag.parse(raw),
            )

        case 'listTransactions':
            return await listTransactionsTool(
                ctx,
                userId,
                toolSchemas.listTransactions.parse(raw),
                clock,
            )
        case 'getTransaction':
            return await getTransactionTool(
                ctx,
                userId,
                toolSchemas.getTransaction.parse(raw),
                clock,
            )
        case 'addExpense':
            return await createMovement(
                ctx,
                userId,
                'expense',
                toolSchemas.addExpense.parse(raw),
                clock,
                writeKey,
            )
        case 'addIncome':
            return await createMovement(
                ctx,
                userId,
                'income',
                toolSchemas.addIncome.parse(raw),
                clock,
                writeKey,
            )
        case 'addTransfer':
            return await addTransferTool(
                ctx,
                userId,
                toolSchemas.addTransfer.parse(raw),
                clock,
                writeKey,
            )
        case 'addBalanceAdjustment':
            return await addBalanceAdjustmentTool(
                ctx,
                userId,
                toolSchemas.addBalanceAdjustment.parse(raw),
                clock,
                writeKey,
            )
        case 'updateTransaction':
            return await updateTransactionTool(
                ctx,
                userId,
                toolSchemas.updateTransaction.parse(raw),
                clock,
            )
        case 'deleteTransaction':
            return await deleteTransactionTool(
                ctx,
                userId,
                toolSchemas.deleteTransaction.parse(raw),
            )
        case 'summarizeTransactions':
            return await summarizeTransactionsTool(
                ctx,
                userId,
                toolSchemas.summarizeTransactions.parse(raw),
                clock,
            )

        case 'addMemory':
            return await addMemoryTool(
                ctx,
                userId,
                toolSchemas.addMemory.parse(raw),
                writeKey,
            )
        case 'updateMemory':
            return await updateMemoryTool(
                ctx,
                userId,
                toolSchemas.updateMemory.parse(raw),
            )
        case 'forgetMemory':
            return await forgetMemoryTool(
                ctx,
                userId,
                toolSchemas.forgetMemory.parse(raw),
            )

        case 'calculate':
            return calculateTool(toolSchemas.calculate.parse(raw))
        case 'calculateDate':
            return calculateDateTool(
                toolSchemas.calculateDate.parse(raw),
                clock,
            )
        case 'readSkill':
            return readSkillTool(toolSchemas.readSkill.parse(raw))

        case 'getExchangeRate':
            return await getExchangeRateTool(
                ctx,
                toolSchemas.getExchangeRate.parse(raw),
                clock,
            )

        default:
            return fail(`Unknown tool: ${name}`)
    }
}

// Executes one tool call.
//
// Returns its result as a JSON string rather than a Convex object: the shape
// differs per tool and only ever travels back to the model, so a validator
// here would buy nothing and cost a union of thirty return types.
//
// Expected, tool-level problems ("Account not found", an ambiguous name) come
// back as an `{ok: false, error}` envelope, because the model can recover from
// those by asking the user.
//
// Unexpected ones — a malformed argument, a failed aggregate write — are
// allowed to throw. That is deliberate: a mutation is a transaction, and
// catching here would commit whatever the handler had already written before
// the failure, leaving a transaction row with no matching aggregate entry and
// a permanently wrong balance. Throwing rolls the whole call back, and the
// caller in `agent/runner.ts` turns it into an error envelope for the model.
export const execute = internalMutation({
    args: {
        userId: v.string(),
        name: v.string(),
        argsJson: v.string(),
        nowMs: v.number(),
        utcOffsetMinutes: v.number(),
        // Present only for callers whose turn can be replayed — the WhatsApp
        // agent. See `agent/idempotency.ts`.
        writeKey: v.optional(v.string()),
    },
    handler: async (ctx, args): Promise<string> => {
        if (!isAgentToolName(args.name)) {
            return JSON.stringify(fail(`Unknown tool: ${args.name}`))
        }
        // A flag-gated tool is already filtered out of the declarations the
        // model is given (`agent/runner.ts`), so this is not a duplicate check
        // but the authoritative one: the executor never takes the model's word
        // for which tools the rollout has reached.
        const flag = flagForTool(args.name)
        if (flag !== undefined) {
            const flags = await resolveFlagsForUser(ctx, args.userId)
            if (!flags[flag]) {
                return JSON.stringify(fail(`Unknown tool: ${args.name}`))
            }
        }
        const raw: unknown = JSON.parse(args.argsJson)
        if (hasUnsupportedRecurrenceArguments(args.name, raw)) {
            return JSON.stringify(
                fail(
                    'Recurring movements and series-wide changes must be managed in the app.',
                ),
            )
        }
        const result = await dispatch(
            ctx,
            args.userId,
            args.name,
            raw,
            { nowMs: args.nowMs, offsetMinutes: args.utcOffsetMinutes },
            args.writeKey,
        )
        return JSON.stringify(result)
    },
})
