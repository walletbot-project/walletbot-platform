import { api } from '@wallet-bot/backend/api'
import type {
    BackgroundMode,
    BreakdownChartKind,
    BreakdownGroupBy,
    DashboardWidth,
    StatAggregation,
    ToolName,
    WidgetOptions,
    WidgetType,
} from '@wallet-bot/shared'
import {
    backgroundToJson,
    collapseEmptyRows,
    DASHBOARD_WIDTHS,
    filterConfigToJson,
    filterFromCanonical,
    isFilterEmpty,
    mergeWidgetOptions,
    parseAmountToCents,
    parseFilterConfig,
    parseOptionalDate,
    parseTransactionDate,
    parseWidgetOptions,
    resolvePlacements,
    toolSchemas,
    WIDGET_TYPES,
} from '@wallet-bot/shared'
import { newId } from '@/lib/new-id'
import {
    type AgentToolContext,
    defineTool,
    resolutionError,
    resolveAccount,
    resolveCategory,
    resolveTag,
    resolveTagIds,
    type ToolExecutor,
} from './helpers'

export const toolExecutors = {
    // ───── Accounts ─────
    listAccounts: defineTool(toolSchemas.listAccounts, async (ctx, args) => {
        const accounts = await ctx.client.query(api.v1.accounts.queries.list, {
            includeArchived: args.includeArchived ?? false,
        })
        return {
            ok: true,
            accounts: accounts.map((a) => ({
                id: a.id,
                name: a.name,
                currency: a.currency,
                color: a.color,
                icon: a.icon,
                isArchived: a.isArchived,
            })),
        }
    }),
    getAccount: defineTool(toolSchemas.getAccount, async (ctx, args) => {
        const r = await resolveAccount(ctx, args.idOrName)
        if (!r.ok) return resolutionError('Account', r)
        return { ok: true, account: r.entity }
    }),
    getAccountBalance: defineTool(
        toolSchemas.getAccountBalance,
        async (ctx, args) => {
            const r = await resolveAccount(ctx, args.idOrName)
            if (!r.ok) return resolutionError('Account', r)
            const balance = await ctx.client.query(
                api.v1.transactions.queries.balance,
                { accountId: r.entity.id },
            )
            if (!balance) return { ok: false, error: 'Account not found' }
            return {
                ok: true,
                accountId: r.entity.id,
                accountName: r.entity.name,
                balance: Number(balance.balance) / 100,
                currency: balance.currency,
            }
        },
    ),
    createAccount: defineTool(toolSchemas.createAccount, async (ctx, args) => {
        const id = newId()
        await ctx.client.mutation(api.v1.accounts.mutations.create, {
            id,
            name: args.name,
            currency: args.currency,
            description: args.description,
            color: args.color,
            icon: args.icon,
        })
        return { ok: true, id }
    }),
    updateAccount: defineTool(toolSchemas.updateAccount, async (ctx, args) => {
        const r = await resolveAccount(ctx, args.idOrName)
        if (!r.ok) return resolutionError('Account', r)
        await ctx.client.mutation(api.v1.accounts.mutations.update, {
            id: r.entity.id,
            name: args.name,
            description: args.description,
            color: args.color,
            icon: args.icon,
        })
        return { ok: true, id: r.entity.id }
    }),
    archiveAccount: defineTool(
        toolSchemas.archiveAccount,
        async (ctx, args) => {
            const r = await resolveAccount(ctx, args.idOrName)
            if (!r.ok) return resolutionError('Account', r)
            await ctx.client.mutation(api.v1.accounts.mutations.archive, {
                id: r.entity.id,
            })
            return { ok: true, id: r.entity.id }
        },
    ),

    // ───── Categories ─────
    listCategories: defineTool(toolSchemas.listCategories, async (ctx) => {
        const cats = await ctx.client.query(
            api.v1.categories.queries.listActive,
        )
        return {
            ok: true,
            categories: cats.map((c) => ({
                id: c.id,
                name: c.name,
                description: c.description,
                color: c.color,
                icon: c.icon,
            })),
        }
    }),
    getCategory: defineTool(toolSchemas.getCategory, async (ctx, args) => {
        const r = await resolveCategory(ctx, args.idOrName)
        if (!r.ok) return resolutionError('Category', r)
        return { ok: true, category: r.entity }
    }),
    createCategory: defineTool(
        toolSchemas.createCategory,
        async (ctx, args) => {
            const id = newId()
            await ctx.client.mutation(api.v1.categories.mutations.create, {
                id,
                name: args.name,
                description: args.description,
                color: args.color,
                icon: args.icon,
            })
            return { ok: true, id }
        },
    ),
    updateCategory: defineTool(
        toolSchemas.updateCategory,
        async (ctx, args) => {
            const r = await resolveCategory(ctx, args.idOrName)
            if (!r.ok) return resolutionError('Category', r)
            await ctx.client.mutation(api.v1.categories.mutations.update, {
                id: r.entity.id,
                name: args.name,
                description: args.description,
                color: args.color,
                icon: args.icon,
            })
            return { ok: true, id: r.entity.id }
        },
    ),
    archiveCategory: defineTool(
        toolSchemas.archiveCategory,
        async (ctx, args) => {
            const r = await resolveCategory(ctx, args.idOrName)
            if (!r.ok) return resolutionError('Category', r)
            await ctx.client.mutation(api.v1.categories.mutations.archive, {
                id: r.entity.id,
            })
            return { ok: true, id: r.entity.id }
        },
    ),

    // ───── Tags ─────
    listTags: defineTool(toolSchemas.listTags, async (ctx) => {
        const tags = await ctx.client.query(api.v1.tags.queries.listActive)
        return {
            ok: true,
            tags: tags.map((t) => ({
                id: t.id,
                name: t.name,
                parentId: t.parentId,
                color: t.color,
            })),
        }
    }),
    getTag: defineTool(toolSchemas.getTag, async (ctx, args) => {
        const r = await resolveTag(ctx, args.idOrName)
        if (!r.ok) return resolutionError('Tag', r)
        return { ok: true, tag: r.entity }
    }),
    createTag: defineTool(toolSchemas.createTag, async (ctx, args) => {
        let parentId: string | undefined
        if (args.parentIdOrName) {
            const r = await resolveTag(ctx, args.parentIdOrName)
            if (!r.ok) return resolutionError('Parent tag', r)
            parentId = r.entity.id
        }
        const id = newId()
        await ctx.client.mutation(api.v1.tags.mutations.create, {
            id,
            name: args.name,
            description: args.description,
            parentId,
            color: args.color,
        })
        return { ok: true, id }
    }),
    updateTag: defineTool(toolSchemas.updateTag, async (ctx, args) => {
        const r = await resolveTag(ctx, args.idOrName)
        if (!r.ok) return resolutionError('Tag', r)
        let parentId: string | null | undefined
        if (args.parentIdOrName !== undefined) {
            const pr = await resolveTag(ctx, args.parentIdOrName)
            if (!pr.ok) return resolutionError('Parent tag', pr)
            parentId = pr.entity.id
        }
        await ctx.client.mutation(api.v1.tags.mutations.update, {
            id: r.entity.id,
            name: args.name,
            description: args.description,
            parentId,
            color: args.color,
        })
        return { ok: true, id: r.entity.id }
    }),
    archiveTag: defineTool(toolSchemas.archiveTag, async (ctx, args) => {
        const r = await resolveTag(ctx, args.idOrName)
        if (!r.ok) return resolutionError('Tag', r)
        await ctx.client.mutation(api.v1.tags.mutations.archive, {
            id: r.entity.id,
        })
        return { ok: true, id: r.entity.id }
    }),

    // ───── Transactions: read ─────
    listTransactions: defineTool(
        toolSchemas.listTransactions,
        async (ctx, args) => {
            let accountId: string | undefined
            if (args.accountIdOrName) {
                const r = await resolveAccount(ctx, args.accountIdOrName)
                if (!r.ok) return resolutionError('Account', r)
                accountId = r.entity.id
            }
            let categoryId: string | undefined
            if (args.categoryIdOrName) {
                const r = await resolveCategory(ctx, args.categoryIdOrName)
                if (!r.ok) return resolutionError('Category', r)
                categoryId = r.entity.id
            }

            const page = await ctx.client.query(
                api.v1.transactions.queries.listPaginated,
                {
                    paginationOpts: {
                        numItems: args.limit ?? 50,
                        cursor: null,
                    },
                    type: args.type,
                    accountId,
                    categoryId,
                    status: args.status,
                    dateFrom: parseOptionalDate(args.dateFrom),
                    dateTo: parseOptionalDate(args.dateTo),
                },
            )

            // Optional tag filter applied client-side because tags are a join.
            let items = page.page
            if (args.tagIdOrName) {
                const tagR = await resolveTag(ctx, args.tagIdOrName)
                if (!tagR.ok) return resolutionError('Tag', tagR)
                const allowed = new Set<string>()
                for (const t of items) {
                    const full = await ctx.client.query(
                        api.v1.transactions.queries.get,
                        { id: t.id },
                    )
                    if (full?.tagIds?.includes(tagR.entity.id))
                        allowed.add(t.id)
                }
                items = items.filter((t) => allowed.has(t.id))
            }

            return {
                ok: true,
                items: items.map(serializeTransaction),
                isDone: page.isDone,
                nextCursor: page.continueCursor,
            }
        },
    ),
    getTransaction: defineTool(
        toolSchemas.getTransaction,
        async (ctx, args) => {
            const txn = await ctx.client.query(
                api.v1.transactions.queries.get,
                {
                    id: args.id,
                },
            )
            if (!txn) return { ok: false, error: 'Transaction not found' }
            return { ok: true, transaction: serializeTransaction(txn) }
        },
    ),
    getRecentTransactions: defineTool(
        toolSchemas.getRecentTransactions,
        async (ctx, args) => {
            const txns = await ctx.client.query(
                api.v1.transactions.queries.recent,
                { limit: args.limit ?? 10 },
            )
            return {
                ok: true,
                items: txns.map(serializeTransaction),
            }
        },
    ),

    // ───── Transactions: write ─────
    addExpense: defineTool(toolSchemas.addExpense, async (ctx, args) => {
        const accR = await resolveAccount(ctx, args.accountIdOrName)
        if (!accR.ok) return resolutionError('Account', accR)
        const catR = await resolveCategory(ctx, args.categoryIdOrName)
        if (!catR.ok) return resolutionError('Category', catR)

        const id = newId()
        const date = parseTransactionDate(args.date, args.timeStatus, args.time)
        await ctx.client.mutation(api.v1.transactions.mutations.createExpense, {
            id,
            name: args.name,
            description: args.description,
            amount: parseAmountToCents(args.amount),
            accountId: accR.entity.id,
            categoryId: catR.entity.id,
            date,
            dateConfirmed: args.date !== undefined,
            timeStatus: args.timeStatus,
            status: args.status,
            createdBy: 'agent',
        })
        await attachTags(ctx, id, args.tagIdsOrNames)
        return { ok: true, id, date: Number(date), timeStatus: args.timeStatus }
    }),
    addIncome: defineTool(toolSchemas.addIncome, async (ctx, args) => {
        const accR = await resolveAccount(ctx, args.accountIdOrName)
        if (!accR.ok) return resolutionError('Account', accR)
        const catR = await resolveCategory(ctx, args.categoryIdOrName)
        if (!catR.ok) return resolutionError('Category', catR)

        const id = newId()
        const date = parseTransactionDate(args.date, args.timeStatus, args.time)
        await ctx.client.mutation(api.v1.transactions.mutations.createIncome, {
            id,
            name: args.name,
            description: args.description,
            amount: parseAmountToCents(args.amount),
            accountId: accR.entity.id,
            categoryId: catR.entity.id,
            date,
            dateConfirmed: args.date !== undefined,
            timeStatus: args.timeStatus,
            status: args.status,
            createdBy: 'agent',
        })
        await attachTags(ctx, id, args.tagIdsOrNames)
        return { ok: true, id, date: Number(date), timeStatus: args.timeStatus }
    }),
    addTransfer: defineTool(toolSchemas.addTransfer, async (ctx, args) => {
        const fromR = await resolveAccount(ctx, args.fromAccountIdOrName)
        if (!fromR.ok) return resolutionError('Source account', fromR)
        const toR = await resolveAccount(ctx, args.toAccountIdOrName)
        if (!toR.ok) return resolutionError('Destination account', toR)

        if (!args.categoryIdOrName) {
            return { ok: false, error: 'Category is required' }
        }
        const catR = await resolveCategory(ctx, args.categoryIdOrName)
        if (!catR.ok) return resolutionError('Category', catR)

        const id = newId()
        const date = parseTransactionDate(args.date, args.timeStatus, args.time)
        await ctx.client.mutation(
            api.v1.transactions.mutations.createTransfer,
            {
                id,
                name: args.name,
                description: args.description,
                amount: parseAmountToCents(args.amount),
                accountId: fromR.entity.id,
                toAccountId: toR.entity.id,
                toAmount:
                    args.toAmount !== undefined
                        ? parseAmountToCents(args.toAmount)
                        : undefined,
                exchangeRate: args.exchangeRate,
                categoryId: catR.entity.id,
                date,
                dateConfirmed: args.date !== undefined,
                timeStatus: args.timeStatus,
                createdBy: 'agent',
            },
        )
        await attachTags(ctx, id, args.tagIdsOrNames)
        return { ok: true, id, date: Number(date), timeStatus: args.timeStatus }
    }),
    addBalanceAdjustment: defineTool(
        toolSchemas.addBalanceAdjustment,
        async (ctx, args) => {
            const accR = await resolveAccount(ctx, args.accountIdOrName)
            if (!accR.ok) return resolutionError('Account', accR)
            const id = newId()
            const date = parseTransactionDate(
                args.date,
                args.timeStatus,
                args.time,
            )
            await ctx.client.mutation(
                api.v1.transactions.mutations.createBalanceAdjustment,
                {
                    id,
                    accountId: accR.entity.id,
                    balanceAfter: parseAmountToCents(args.balanceAfter),
                    name: args.name,
                    description: args.description,
                    date,
                    dateConfirmed: args.date !== undefined,
                    timeStatus: args.timeStatus,
                    createdBy: 'agent',
                },
            )
            return {
                ok: true,
                id,
                date: Number(date),
                timeStatus: args.timeStatus,
            }
        },
    ),
    updateTransaction: defineTool(
        toolSchemas.updateTransaction,
        async (ctx, args) => {
            let categoryId: string | undefined
            if (args.categoryIdOrName) {
                const r = await resolveCategory(ctx, args.categoryIdOrName)
                if (!r.ok) return resolutionError('Category', r)
                categoryId = r.entity.id
            }
            // Partial temporal edits must preserve whichever of the calendar
            // date / clock the caller omitted, instead of anchoring the
            // missing half to "now". We read the existing transaction and
            // backfill the omitted component from its stored timestamp. The
            // status forced into `parseTransactionDate` only drives parsing
            // (an explicit clock is always respected); the persisted
            // `timeStatus` is `args.timeStatus`, handled separately below.
            let date: bigint | undefined
            if (args.date !== undefined || args.time !== undefined) {
                const existing = await ctx.client.query(
                    api.v1.transactions.queries.get,
                    { id: args.id },
                )
                if (!existing) {
                    return { ok: false, error: 'Transaction not found' }
                }
                const existingDate = new Date(Number(existing.date))
                const pad = (n: number) => String(n).padStart(2, '0')
                const dateInput =
                    args.date ??
                    `${existingDate.getFullYear()}-${pad(
                        existingDate.getMonth() + 1,
                    )}-${pad(existingDate.getDate())}`
                const timeInput =
                    args.time ??
                    `${pad(existingDate.getHours())}:${pad(
                        existingDate.getMinutes(),
                    )}`
                date = parseTransactionDate(dateInput, 'confirmed', timeInput)
            }
            await ctx.client.mutation(api.v1.transactions.mutations.update, {
                id: args.id,
                name: args.name,
                description: args.description,
                date,
                dateConfirmed: args.date === undefined ? undefined : true,
                timeStatus: args.timeStatus,
                amount:
                    args.amount !== undefined
                        ? parseAmountToCents(args.amount)
                        : undefined,
                categoryId,
                status: args.status,
            })
            return {
                ok: true,
                id: args.id,
                ...(date === undefined ? {} : { date: Number(date) }),
                ...(args.timeStatus === undefined
                    ? {}
                    : { timeStatus: args.timeStatus }),
            }
        },
    ),
    deleteTransaction: defineTool(
        toolSchemas.deleteTransaction,
        async (ctx, args) => {
            await ctx.client.mutation(api.v1.transactions.mutations.archive, {
                id: args.id,
            })
            return { ok: true, id: args.id }
        },
    ),
    tagTransaction: defineTool(
        toolSchemas.tagTransaction,
        async (ctx, args) => {
            const { resolved, missing } = await resolveTagIds(
                ctx,
                args.tagIdsOrNames,
            )
            if (resolved.length === 0) {
                return { ok: false, error: 'No tags resolved', missing }
            }
            const result = await ctx.client.mutation(
                api.v1.transactions.mutations.tag,
                {
                    transactionId: args.transactionId,
                    tagIds: resolved,
                },
            )
            return { ok: true, ...result, missing }
        },
    ),
    untagTransaction: defineTool(
        toolSchemas.untagTransaction,
        async (ctx, args) => {
            const { resolved, missing } = await resolveTagIds(
                ctx,
                args.tagIdsOrNames,
            )
            const result = await ctx.client.mutation(
                api.v1.transactions.mutations.untag,
                {
                    transactionId: args.transactionId,
                    tagIds: resolved,
                },
            )
            return { ok: true, ...result, missing }
        },
    ),

    // ───── Summaries ─────
    // TODO(aggregates): these currently walk the listPaginated index over the
    // date range, which is bounded but suboptimal. Replace with the aggregate
    // component once Phase 2 is wired up.
    summarizeByCategory: defineTool(
        toolSchemas.summarizeByCategory,
        async (ctx, args) => {
            const dateFrom = parseOptionalDate(args.dateFrom)
            const dateTo = parseOptionalDate(args.dateTo)
            const items = await collectAllInRange(ctx, {
                dateFrom,
                dateTo,
                type: args.type,
            })
            const totals = new Map<string, bigint>()
            for (const t of items) {
                if (args.currency && t.currency !== args.currency) continue
                if (t.type === 'transfer') continue
                const key = t.categoryId
                totals.set(key, (totals.get(key) ?? 0n) + t.amount)
            }
            const cats = await ctx.client.query(
                api.v1.categories.queries.listActive,
            )
            const nameById = new Map(cats.map((c) => [c.id, c.name]))
            return {
                ok: true,
                rows: Array.from(totals.entries()).map(
                    ([categoryId, total]) => ({
                        categoryId,
                        name: nameById.get(categoryId) ?? '(unknown)',
                        total: Number(total) / 100,
                    }),
                ),
            }
        },
    ),
    summarizeByAccount: defineTool(
        toolSchemas.summarizeByAccount,
        async (ctx, args) => {
            const dateFrom = parseOptionalDate(args.dateFrom)
            const dateTo = parseOptionalDate(args.dateTo)
            const items = await collectAllInRange(ctx, { dateFrom, dateTo })
            const rows = new Map<
                string,
                { name: string; currency: string; in: bigint; out: bigint }
            >()
            const accounts = await ctx.client.query(
                api.v1.accounts.queries.list,
                {
                    includeArchived: false,
                },
            )
            for (const a of accounts) {
                rows.set(a.id, {
                    name: a.name,
                    currency: a.currency,
                    in: 0n,
                    out: 0n,
                })
            }
            for (const t of items) {
                const row = rows.get(t.accountId)
                if (row) {
                    if (t.type === 'expense') row.out += t.amount
                    else if (t.type === 'income') row.in += t.amount
                    else if (t.type === 'transfer') row.out += t.amount
                    else if (t.type === 'balance_adjustment') {
                        if (t.amount >= 0n) row.in += t.amount
                        else row.out += -t.amount
                    }
                }
                if (t.type === 'transfer' && t.toAccountId) {
                    const dest = rows.get(t.toAccountId)
                    if (dest) dest.in += t.toAmount ?? t.amount
                }
            }
            return {
                ok: true,
                rows: Array.from(rows.entries()).map(([accountId, r]) => ({
                    accountId,
                    name: r.name,
                    currency: r.currency,
                    in: Number(r.in) / 100,
                    out: Number(r.out) / 100,
                    net: Number(r.in - r.out) / 100,
                })),
            }
        },
    ),

    // ───── Home dashboard: saved filters ─────
    //
    // Ported from the native executors (apps/native/lib/voice/tool_executors.dart,
    // § "Saved filter tools" / "Dashboard widget tools"): same arguments, same
    // error strings, same result shapes and the same stored JSON, so one tool
    // call means the same thing on both clients. Web reaches the rows through
    // Convex instead of Drift; the dashboard itself already writes them
    // (apps/web/src/pages/home/widget-sheet.tsx).
    listSavedFilters: defineTool(toolSchemas.listSavedFilters, async (ctx) => {
        const layout = await ctx.client.query(api.v1.dashboard.queries.layout)
        return { ok: true, filters: layout.filters.map(serializeSavedFilter) }
    }),
    createSavedFilter: defineTool(
        toolSchemas.createSavedFilter,
        async (ctx, args) => {
            const name = args.name.trim()
            if (!name) return { ok: false, error: 'Filter name is required' }
            const id = newId()
            await ctx.client.mutation(
                api.v1.dashboard.mutations.createSavedFilter,
                {
                    id,
                    name,
                    config: canonicalFilterConfig(args.filterConfigJson),
                },
            )
            return { ok: true, id }
        },
    ),
    updateSavedFilter: defineTool(
        toolSchemas.updateSavedFilter,
        async (ctx, args) => {
            // `layout` only returns live filters, so a miss covers both "never
            // existed" and "archived" — the two cases native rejects together.
            const layout = await ctx.client.query(
                api.v1.dashboard.queries.layout,
            )
            if (!layout.filters.some((filter) => filter.id === args.id)) {
                return { ok: false, error: 'Saved filter not found' }
            }
            await ctx.client.mutation(
                api.v1.dashboard.mutations.updateSavedFilter,
                {
                    id: args.id,
                    ...(args.name === undefined
                        ? {}
                        : { name: args.name.trim() }),
                    ...(args.filterConfigJson === undefined
                        ? {}
                        : {
                              config: canonicalFilterConfig(
                                  args.filterConfigJson,
                              ),
                          }),
                },
            )
            return { ok: true, id: args.id }
        },
    ),
    archiveSavedFilter: defineTool(
        toolSchemas.archiveSavedFilter,
        async (ctx, args) => {
            await ctx.client.mutation(
                api.v1.dashboard.mutations.archiveSavedFilter,
                { id: args.id },
            )
            return { ok: true, id: args.id }
        },
    ),

    // ───── Home dashboard: widgets ─────
    listDashboardWidgets: defineTool(
        toolSchemas.listDashboardWidgets,
        async (ctx) => {
            const layout = await ctx.client.query(
                api.v1.dashboard.queries.layout,
            )
            const filtersById = new Map(
                layout.filters.map((filter) => [filter.id, filter]),
            )
            return {
                ok: true,
                widgets: layout.widgets.map((widget) =>
                    serializeDashboardWidget(widget, filtersById),
                ),
            }
        },
    ),
    createDashboardWidget: defineTool(
        toolSchemas.createDashboardWidget,
        async (ctx, args) => {
            const title = args.title.trim()
            if (!title) {
                return { ok: false, error: 'Widget title is required' }
            }
            const built = widgetOptionsFor(
                args.type,
                title,
                args,
                parseWidgetOptions(''),
            )
            if ('error' in built) return { ok: false, error: built.error }

            const layout = await ctx.client.query(
                api.v1.dashboard.queries.layout,
            )
            const filterId = await createFilterForWidget(
                ctx,
                args.type,
                title,
                args.filterConfigJson,
            )
            const id = newId()
            await ctx.client.mutation(api.v1.dashboard.mutations.createWidget, {
                id,
                type: args.type,
                ...(filterId ? { filterId } : {}),
                position: layout.widgets.length,
                width: args.width ?? defaultWidthFor(args.type),
                // A new tile lands on a fresh row below everything placed, so
                // it can never overlap what is already there.
                options: mergeWidgetOptions('', {
                    ...built.options,
                    layout: { row: nextFreeRow(layout.widgets), col: 0 },
                }),
            })
            return { ok: true, id, filterId }
        },
    ),
    updateDashboardWidget: defineTool(
        toolSchemas.updateDashboardWidget,
        async (ctx, args) => {
            const layout = await ctx.client.query(
                api.v1.dashboard.queries.layout,
            )
            const existing = layout.widgets.find(
                (widget) => widget.id === args.id,
            )
            if (!existing) {
                return { ok: false, error: 'Dashboard widget not found' }
            }

            const currentOptions = parseWidgetOptions(existing.options)
            // A widget stored with a type this build doesn't know (written by a
            // newer client) is refused rather than rewritten as something else.
            const nextType = args.type ?? asWidgetType(existing.type)
            if (nextType === null) {
                return { ok: false, error: 'Invalid widget type' }
            }
            const title = (args.title ?? currentOptions.title).trim()
            if (!title) {
                return { ok: false, error: 'Widget title is required' }
            }
            const built = widgetOptionsFor(
                nextType,
                title,
                args,
                currentOptions,
            )
            if ('error' in built) return { ok: false, error: built.error }

            const filterId = await filterIdForWidgetUpdate(ctx, {
                existingFilterId: existing.filterId,
                type: nextType,
                title,
                filterConfigJson: args.filterConfigJson,
                titleChanged: args.title !== undefined,
            })
            await ctx.client.mutation(api.v1.dashboard.mutations.updateWidget, {
                id: args.id,
                ...(args.type === undefined ? {} : { type: args.type }),
                // Always sent: an explicit null is how a widget drops its
                // filter when it becomes a balance card.
                filterId,
                ...(args.width === undefined ? {} : { width: args.width }),
                options: mergeWidgetOptions(existing.options, built.options),
            })
            return { ok: true, id: args.id, filterId }
        },
    ),
    reorderDashboardWidgets: defineTool(
        toolSchemas.reorderDashboardWidgets,
        async (ctx, args) => {
            // Native reorders by writing `position = index` in one transaction;
            // `saveLayout` is web's transactional equivalent, so width and
            // options go back unchanged and only the position moves. Ids that
            // name no live widget are skipped without shifting the rest, the
            // way native's `UPDATE ... WHERE id = ?` simply matches nothing.
            const layout = await ctx.client.query(
                api.v1.dashboard.queries.layout,
            )
            const byId = new Map(
                layout.widgets.map((widget) => [widget.id, widget]),
            )
            await ctx.client.mutation(api.v1.dashboard.mutations.saveLayout, {
                widgets: args.ids.flatMap((id, index) => {
                    const widget = byId.get(id)
                    if (!widget) return []
                    return [
                        {
                            id,
                            position: index,
                            width: widget.width,
                            options: widget.options,
                        },
                    ]
                }),
            })
            return { ok: true, ids: args.ids }
        },
    ),
    archiveDashboardWidget: defineTool(
        toolSchemas.archiveDashboardWidget,
        async (ctx, args) => {
            await ctx.client.mutation(
                api.v1.dashboard.mutations.archiveWidget,
                { id: args.id },
            )
            return { ok: true, id: args.id }
        },
    ),
} satisfies Record<ToolName, ToolExecutor>

// ───── Local helpers ─────

type TxnLite = {
    id: string
    type: 'expense' | 'income' | 'transfer' | 'balance_adjustment'
    name: string
    date: bigint
    dateConfirmed?: boolean
    timeStatus?: 'confirmed' | 'approximation' | 'none'
    accountId: string
    categoryId: string
    amount: bigint
    currency: string
    toAccountId?: string
    toAmount?: bigint
    status: 'pending' | 'cleared'
    balanceAfter?: bigint
    tagIds?: string[]
}

function serializeTransaction(t: TxnLite) {
    return {
        id: t.id,
        type: t.type,
        name: t.name,
        date: Number(t.date),
        dateConfirmed: t.dateConfirmed,
        timeStatus: t.timeStatus ?? 'none',
        accountId: t.accountId,
        categoryId: t.categoryId,
        amount: Number(t.amount) / 100,
        currency: t.currency,
        toAccountId: t.toAccountId,
        toAmount:
            t.toAmount !== undefined ? Number(t.toAmount) / 100 : undefined,
        status: t.status,
        balanceAfter:
            t.balanceAfter !== undefined
                ? Number(t.balanceAfter) / 100
                : undefined,
        tagIds: t.tagIds,
    }
}

async function attachTags(
    ctx: { client: import('convex/react').ConvexReactClient },
    transactionId: string,
    tagIdsOrNames: string[] | undefined,
) {
    if (!tagIdsOrNames || tagIdsOrNames.length === 0) return
    const { resolved } = await resolveTagIds(ctx, tagIdsOrNames)
    if (resolved.length === 0) return
    await ctx.client.mutation(api.v1.transactions.mutations.tag, {
        transactionId,
        tagIds: resolved,
    })
}

async function collectAllInRange(
    ctx: { client: import('convex/react').ConvexReactClient },
    args: {
        dateFrom?: bigint
        dateTo?: bigint
        type?: 'expense' | 'income' | 'transfer'
    },
): Promise<TxnLite[]> {
    const out: TxnLite[] = []
    let cursor: string | null = null
    let isDone = false
    let safety = 50 // hard cap on pages — each is 200 items
    while (!isDone && safety > 0) {
        const page: {
            page: TxnLite[]
            isDone: boolean
            continueCursor: string
        } = await ctx.client.query(api.v1.transactions.queries.listPaginated, {
            paginationOpts: { numItems: 200, cursor },
            type: args.type,
            dateFrom: args.dateFrom,
            dateTo: args.dateTo,
        })
        out.push(...page.page)
        cursor = page.continueCursor
        isDone = page.isDone
        safety -= 1
    }
    return out
}

// ───── Dashboard helpers ─────
//
// The counterparts of the private helpers at the bottom of native's
// `tool_executors.dart`. Keeping the same shapes here is what makes a dashboard
// built by voice on a phone editable from the browser and vice versa.

type SavedFilterRow = { id: string; name: string; config: string }

type DashboardWidgetRow = {
    id: string
    type: string
    filterId: string | null
    position: number
    width: string
    options: string
}

/** The optional per-type display arguments both widget tools accept. */
type WidgetContentArgs = {
    aggregation?: StatAggregation
    limit?: number
    currency?: string
    accountIds?: string[]
    groupBy?: BreakdownGroupBy
    chartKind?: BreakdownChartKind
    background?: {
        mode: BackgroundMode
        fixedColor?: string
        low?: number
        high?: number
        lowColor?: string
        betweenColor?: string
        highColor?: string
    }
}

function serializeSavedFilter(filter: SavedFilterRow) {
    return {
        id: filter.id,
        name: filter.name,
        filterConfigJson: filter.config,
        filterConfig: decodeJson(filter.config),
    }
}

function serializeDashboardWidget(
    widget: DashboardWidgetRow,
    filtersById: Map<string, SavedFilterRow>,
) {
    const filter = widget.filterId
        ? (filtersById.get(widget.filterId) ?? null)
        : null
    return {
        id: widget.id,
        type: widget.type,
        filterId: widget.filterId,
        position: widget.position,
        width: widget.width,
        options: decodeJson(widget.options),
        filterConfigJson: filter?.config ?? null,
        filterConfig: filter ? decodeJson(filter.config) : null,
    }
}

/** Parsed JSON, or the raw string when it isn't JSON — native's `_decodeJson`. */
function decodeJson(raw: string): unknown {
    if (!raw) return null
    try {
        return JSON.parse(raw)
    } catch {
        return raw
    }
}

/**
 * Re-serializes a model-supplied filter through the shared model, so whatever
 * shorthand the model wrote is stored in exactly the form every client reads
 * back. An advanced tree survives untouched via `advancedRoot`.
 */
function canonicalFilterConfig(raw: string): string {
    const decoded: unknown = JSON.parse(raw)
    if (typeof decoded !== 'object' || decoded === null) {
        throw new Error('Filter config must be a JSON object')
    }
    return filterConfigToJson(filterFromCanonical(decoded))
}

/**
 * The row a new tile lands on: one past the last occupied row, counted the way
 * native's `DashboardGridLayout.rowCount` counts it — over the *normalized*
 * layout, so a gap left by a deleted tile doesn't push the new one further down
 * than the grid actually renders.
 */
function nextFreeRow(widgets: DashboardWidgetRow[]): number {
    const { placements } = resolvePlacements(
        widgets.map((widget) => ({
            id: widget.id,
            width: asDashboardWidth(widget.width),
            coord: parseWidgetOptions(widget.options).layout,
        })),
    )
    return collapseEmptyRows(placements).reduce(
        (rows, placement) => Math.max(rows, placement.row + 1),
        0,
    )
}

function asDashboardWidth(width: string): DashboardWidth {
    return (DASHBOARD_WIDTHS as readonly string[]).includes(width)
        ? (width as DashboardWidth)
        : 'full'
}

function asWidgetType(type: string): WidgetType | null {
    return (WIDGET_TYPES as readonly string[]).includes(type)
        ? (type as WidgetType)
        : null
}

function defaultWidthFor(type: WidgetType): DashboardWidth {
    switch (type) {
        case 'stat':
            return 'third'
        case 'balance':
            return 'half'
        default:
            return 'full'
    }
}

/**
 * The content half of a widget's `options`: only the keys its type uses, plus
 * the background. Anything the caller left out keeps the widget's current
 * value, so a partial update never blanks a field it didn't mention.
 */
function widgetOptionsFor(
    type: WidgetType,
    title: string,
    args: WidgetContentArgs,
    existing: WidgetOptions,
): { options: Record<string, unknown> } | { error: string } {
    const options: Record<string, unknown> = { title }
    switch (type) {
        case 'stat':
            options.aggregation = args.aggregation ?? existing.aggregation
            break
        case 'list':
            options.limit =
                args.limit !== undefined && args.limit > 0
                    ? Math.trunc(args.limit)
                    : existing.limit
            break
        case 'balance': {
            const currency = (args.currency ?? existing.currency).trim()
            if (!currency) {
                return { error: 'Balance widgets require currency' }
            }
            options.currency = currency.toUpperCase()
            // `accountIds` is a content key, so it is dropped before the merge:
            // it has to be re-stated on every write or a partial update that
            // never mentioned it would silently widen the card back to the
            // whole currency.
            options.accountIds = args.accountIds ?? existing.accountIds
            break
        }
        case 'chart':
            options.groupBy = args.groupBy ?? existing.groupBy
            options.chartKind = args.chartKind ?? existing.chartKind
            break
    }

    const background =
        args.background === undefined
            ? backgroundToJson(existing.background)
            : backgroundFromArgs(args.background)
    if (background) options.background = background
    return { options }
}

/**
 * The flat background the tool schema declares, in the nested shape the stored
 * options use. The literals are native's tool-executor defaults rather than
 * `DEFAULT_VALUE_BACKGROUND` on purpose: the same tool call has to store the
 * same JSON on both clients.
 */
function backgroundFromArgs(
    background: NonNullable<WidgetContentArgs['background']>,
): Record<string, unknown> | null {
    switch (background.mode) {
        case 'none':
            return null
        case 'fixed':
            return {
                mode: 'fixed',
                fixedColor: hexColor(background.fixedColor) ?? '#C8F2D8',
            }
        case 'value':
            return {
                mode: 'value',
                value: {
                    low: background.low ?? 0,
                    high: background.high ?? 10000,
                    lowColor: hexColor(background.lowColor) ?? '#FFCBCB',
                    betweenColor:
                        hexColor(background.betweenColor) ?? '#FFE588',
                    highColor: hexColor(background.highColor) ?? '#C8F2D8',
                },
            }
    }
}

/** A colour the model may have written without its leading `#`. */
function hexColor(raw: string | undefined): string | null {
    const trimmed = raw?.trim()
    if (!trimmed) return null
    return trimmed.startsWith('#') ? trimmed : `#${trimmed}`
}

/** The saved filter a brand-new widget binds to, or null when it needs none. */
async function createFilterForWidget(
    ctx: AgentToolContext,
    type: WidgetType,
    title: string,
    filterConfigJson: string | undefined,
): Promise<string | null> {
    if (type === 'balance' || filterConfigJson === undefined) return null
    const config = canonicalFilterConfig(filterConfigJson)
    if (isFilterEmpty(parseFilterConfig(config))) return null
    const id = newId()
    await ctx.client.mutation(api.v1.dashboard.mutations.createSavedFilter, {
        id,
        name: title,
        config,
    })
    return id
}

/**
 * The saved filter an updated widget ends up bound to: a new config edits the
 * one it already has (or creates one), a balance card drops it, and a bare
 * rename follows through to the filter's own name.
 */
async function filterIdForWidgetUpdate(
    ctx: AgentToolContext,
    args: {
        existingFilterId: string | null
        type: WidgetType
        title: string
        filterConfigJson: string | undefined
        titleChanged: boolean
    },
): Promise<string | null> {
    if (args.type === 'balance') return null

    if (args.filterConfigJson !== undefined) {
        const config = canonicalFilterConfig(args.filterConfigJson)
        if (isFilterEmpty(parseFilterConfig(config))) return null
        if (args.existingFilterId) {
            await ctx.client.mutation(
                api.v1.dashboard.mutations.updateSavedFilter,
                { id: args.existingFilterId, name: args.title, config },
            )
            return args.existingFilterId
        }
        const id = newId()
        await ctx.client.mutation(
            api.v1.dashboard.mutations.createSavedFilter,
            { id, name: args.title, config },
        )
        return id
    }

    if (args.existingFilterId && args.titleChanged) {
        await ctx.client.mutation(
            api.v1.dashboard.mutations.updateSavedFilter,
            { id: args.existingFilterId, name: args.title },
        )
    }
    return args.existingFilterId
}
