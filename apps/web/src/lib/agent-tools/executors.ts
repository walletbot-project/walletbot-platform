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
    AGENT_SKILLS,
    AGENT_SKILLS_BY_SLUG,
    backgroundToJson,
    balanceAsOfMs,
    collapseEmptyRows,
    convertAmount,
    DASHBOARD_WIDTHS,
    DEFAULT_FX_MARKET,
    filterConfigToJson,
    filterFromCanonical,
    fxAlternatives,
    isFilterEmpty,
    isFxQuoteStale,
    isValidCurrencyCode,
    mergeWidgetOptions,
    normalizeCurrencyCode,
    parseAmountToCents,
    parseFilterConfig,
    parseNaturalDate,
    parseOptionalDate,
    parseTransactionDate,
    parseWidgetOptions,
    pastCutoffBigInt,
    resolveFxQuote,
    resolvePlacements,
    runCalculate,
    runCalculateDate,
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
            // With a date, the balance at the end of that day on this
            // device's calendar; without one, the balance right now.
            const asOfMs =
                args.date === undefined
                    ? pastCutoffBigInt()
                    : balanceAsOfMs(args.date)
            const balance = await ctx.client.query(
                api.v1.transactions.queries.balance,
                { accountId: r.entity.id, asOfMs },
            )
            if (!balance) return { ok: false, error: 'Account not found' }
            return {
                ok: true,
                accountId: r.entity.id,
                accountName: r.entity.name,
                balance: Number(balance.balance) / 100,
                currency: balance.currency,
                ...(args.date !== undefined ? { date: args.date } : {}),
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
    listCategories: defineTool(
        toolSchemas.listCategories,
        async (ctx, args) => {
            const cats = await ctx.client.query(
                api.v1.categories.queries.list,
                { includeArchived: args.includeArchived ?? false },
            )
            return {
                ok: true,
                categories: cats.map((c) => ({
                    id: c.id,
                    name: c.name,
                    description: c.description,
                    color: c.color,
                    icon: c.icon,
                    isArchived: c.isArchived,
                })),
            }
        },
    ),
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
    listTags: defineTool(toolSchemas.listTags, async (ctx, args) => {
        const tags = await ctx.client.query(api.v1.tags.queries.list, {
            includeArchived: args.includeArchived ?? false,
        })
        return {
            ok: true,
            tags: tags.map((t) => ({
                id: t.id,
                name: t.name,
                parentId: t.parentId,
                color: t.color,
                isArchived: t.isArchived,
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

            // With no filters at all this is the "recent movements" read the
            // old getRecentTransactions tool used to serve: default to 10.
            const hasFilters =
                args.type !== undefined ||
                args.accountIdOrName !== undefined ||
                args.categoryIdOrName !== undefined ||
                args.tagIdOrName !== undefined ||
                args.status !== undefined ||
                args.dateFrom !== undefined ||
                args.dateTo !== undefined
            const page = await ctx.client.query(
                api.v1.transactions.queries.listPaginated,
                {
                    paginationOpts: {
                        numItems: args.limit ?? (hasFilters ? 50 : 10),
                        cursor: null,
                    },
                    asOfMs: pastCutoffBigInt(),
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
            // The series it belongs to, when it belongs to one: the model
            // needs to know before it can offer the user a scope choice.
            const series = await ctx.client.query(
                api.v1.recurrences.queries.get,
                {
                    recurrenceId: txn.recurrenceId,
                    occurrenceIndex: txn.recurrenceIndex,
                },
            )
            return {
                ok: true,
                transaction: {
                    ...serializeTransaction(txn),
                    ...(series === null
                        ? {}
                        : { recurrence: serializeSeries(series) }),
                },
            }
        },
    ),
    // The other side of the occurrence cutoff. Ascending, because the soonest
    // movement is the interesting one.
    listUpcomingTransactions: defineTool(
        toolSchemas.listUpcomingTransactions,
        async (ctx, args) => {
            const page = await ctx.client.query(
                api.v1.transactions.queries.listUpcoming,
                {
                    paginationOpts: {
                        numItems: args.limit ?? 20,
                        cursor: null,
                    },
                    asOfMs: pastCutoffBigInt(),
                },
            )
            return {
                ok: true,
                items: page.page.map(serializeTransaction),
            }
        },
    ),
    listRecurrences: defineTool(toolSchemas.listRecurrences, async (ctx) => {
        const items = await ctx.client.query(
            api.v1.recurrences.queries.list,
            {},
        )
        return {
            ok: true,
            items: items.map((rule) => ({
                id: rule.id,
                name: rule.name,
                type: rule.type,
                amount: rule.amount === null ? null : Number(rule.amount) / 100,
                currency: rule.currency,
                accountId: rule.accountId,
                categoryId: rule.categoryId,
                frequency: rule.frequency,
                dayInterval:
                    rule.dayInterval === undefined
                        ? undefined
                        : Number(rule.dayInterval),
                anchorDate: Number(rule.anchorDate),
                endDate:
                    rule.endDate === undefined
                        ? undefined
                        : Number(rule.endDate),
                coveredThrough:
                    rule.coveredThroughMs === null
                        ? null
                        : Number(rule.coveredThroughMs),
            })),
        }
    }),
    // ───── Transactions: write ─────
    addExpense: defineTool(toolSchemas.addExpense, async (ctx, args) => {
        const accR = await resolveAccount(ctx, args.accountIdOrName)
        if (!accR.ok) return resolutionError('Account', accR)
        const catR = await resolveCategory(ctx, args.categoryIdOrName)
        if (!catR.ok) return resolutionError('Category', catR)

        const recurrence = parseRecurrence(args.recurrence)
        if (!recurrence.ok) return { ok: false, error: recurrence.error }

        const id = newId()
        const date = parseTransactionDate(args.date, args.timeStatus, args.time)
        if (recurrence.value !== undefined) {
            // The rule and its whole series, in one call: `create` writes the
            // rule plus occurrence 0 atomically and hands the rest to a
            // workflow.
            const recurrenceId = newId()
            await ctx.client.mutation(api.v1.recurrences.mutations.create, {
                recurrenceId,
                frequency: recurrence.value.frequency,
                dayInterval: recurrence.value.dayInterval,
                endDate: recurrence.value.endDate,
                transactionId: id,
                type: 'expense',
                name: args.name,
                description: args.description,
                amount: parseAmountToCents(args.amount),
                accountId: accR.entity.id,
                categoryId: catR.entity.id,
                date,
                dateConfirmed: args.date !== undefined,
                timeStatus: args.timeStatus,
                createdBy: 'agent',
            })
            await attachTags(ctx, id, args.tagIdsOrNames)
            return {
                ok: true,
                id,
                date: Number(date),
                timeStatus: args.timeStatus,
                ...(await seriesResult(ctx, recurrenceId, 0n)),
            }
        }
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

        const recurrence = parseRecurrence(args.recurrence)
        if (!recurrence.ok) return { ok: false, error: recurrence.error }

        const id = newId()
        const date = parseTransactionDate(args.date, args.timeStatus, args.time)
        if (recurrence.value !== undefined) {
            // The rule and its whole series, in one call: `create` writes the
            // rule plus occurrence 0 atomically and hands the rest to a
            // workflow.
            const recurrenceId = newId()
            await ctx.client.mutation(api.v1.recurrences.mutations.create, {
                recurrenceId,
                frequency: recurrence.value.frequency,
                dayInterval: recurrence.value.dayInterval,
                endDate: recurrence.value.endDate,
                transactionId: id,
                type: 'income',
                name: args.name,
                description: args.description,
                amount: parseAmountToCents(args.amount),
                accountId: accR.entity.id,
                categoryId: catR.entity.id,
                date,
                dateConfirmed: args.date !== undefined,
                timeStatus: args.timeStatus,
                createdBy: 'agent',
            })
            await attachTags(ctx, id, args.tagIdsOrNames)
            return {
                ok: true,
                id,
                date: Number(date),
                timeStatus: args.timeStatus,
                ...(await seriesResult(ctx, recurrenceId, 0n)),
            }
        }
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

        // Category is optional on transfers (they are excluded from category
        // breakdowns anyway); when absent, the backend stores the same '' the
        // native app writes.
        let categoryId: string | undefined
        if (args.categoryIdOrName) {
            const catR = await resolveCategory(ctx, args.categoryIdOrName)
            if (!catR.ok) return resolutionError('Category', catR)
            categoryId = catR.entity.id
        }

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
                categoryId,
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
                    asOfMs: pastCutoffBigInt(),
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

            const allFuture = args.scope === 'all-future'
            const recurrence = parseRecurrence(args.recurrence)
            if (!recurrence.ok) return { ok: false, error: recurrence.error }
            if (recurrence.value !== undefined && !allFuture) {
                return {
                    ok: false,
                    error: 'Changing the cadence needs scope all-future: the occurrences before this one keep their own spacing, so it cannot apply to one movement.',
                }
            }
            if (recurrence.value !== undefined) {
                return await splitSeries(
                    ctx,
                    args,
                    recurrence.value,
                    categoryId,
                )
            }
            if (allFuture) {
                return await updateFuture(ctx, args, categoryId)
            }

            // Tag changes ride the same mutation as the field edits, so
            // everything commits atomically. Unknown names are skipped and
            // reported back in `missing` (never created on the fly).
            const missing: string[] = []
            let addTagIds: string[] | undefined
            if (args.addTagIdsOrNames && args.addTagIdsOrNames.length > 0) {
                const r = await resolveTagIds(ctx, args.addTagIdsOrNames)
                addTagIds = r.resolved
                missing.push(...r.missing)
            }
            let removeTagIds: string[] | undefined
            if (
                args.removeTagIdsOrNames &&
                args.removeTagIdsOrNames.length > 0
            ) {
                const r = await resolveTagIds(ctx, args.removeTagIdsOrNames)
                removeTagIds = r.resolved
                missing.push(...r.missing)
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
                addTagIds,
                removeTagIds,
            })
            return {
                ok: true,
                id: args.id,
                ...(date === undefined ? {} : { date: Number(date) }),
                ...(args.timeStatus === undefined
                    ? {}
                    : { timeStatus: args.timeStatus }),
                ...(missing.length === 0 ? {} : { missing }),
                scope: 'only-this',
            }
        },
    ),
    deleteTransaction: defineTool(
        toolSchemas.deleteTransaction,
        async (ctx, args) => {
            if (args.scope === 'all-future') {
                // Also truncates the rule, so nothing new is created past
                // here. On a movement with no series this degrades to
                // deleting that one.
                await ctx.client.mutation(
                    api.v1.recurrences.mutations.deleteFuture,
                    { transactionId: args.id },
                )
                return { ok: true, id: args.id, scope: 'all-future' }
            }
            await ctx.client.mutation(api.v1.transactions.mutations.archive, {
                id: args.id,
            })
            return { ok: true, id: args.id, scope: 'only-this' }
        },
    ),
    // Extends an open-ended rule by another batch, from the last occurrence
    // that exists.
    addRecurrenceOccurrences: defineTool(
        toolSchemas.addRecurrenceOccurrences,
        async (ctx, args) => {
            try {
                const added = await ctx.client.mutation(
                    api.v1.recurrences.mutations.addOccurrences,
                    { recurrenceId: args.recurrenceId },
                )
                const series = await ctx.client.query(
                    api.v1.recurrences.queries.get,
                    { recurrenceId: args.recurrenceId },
                )
                return {
                    ok: true,
                    recurrenceId: args.recurrenceId,
                    added,
                    coveredThrough:
                        series?.coveredThroughMs === null ||
                        series?.coveredThroughMs === undefined
                            ? null
                            : Number(series.coveredThroughMs),
                }
            } catch {
                return {
                    ok: false,
                    error: 'That rule cannot be extended: it either has an end date (so the series is already complete) or no longer exists.',
                }
            }
        },
    ),
    // ───── Summaries ─────
    // Computed server-side over the bounded, index-anchored scan in
    // `v1/transactions/queries:summarize` (native computes the same shapes
    // locally over Drift — `SummaryRepository.byCategory` / `byAccount`).
    summarizeTransactions: defineTool(
        toolSchemas.summarizeTransactions,
        async (ctx, args) => {
            const dateFrom = parseNaturalDate(args.dateFrom)
            const dateTo = parseNaturalDate(args.dateTo)
            const result = await ctx.client.query(
                api.v1.transactions.queries.summarize,
                {
                    groupBy: args.groupBy,
                    dateFrom,
                    dateTo,
                    asOfMs: pastCutoffBigInt(),
                    type: args.type,
                    currency: args.currency,
                },
            )
            if (result.groupBy === 'category') {
                return {
                    ok: true,
                    ...(result.truncated ? { truncated: true } : {}),
                    rows: result.rows.map((row) => ({
                        categoryId: row.categoryId,
                        name: row.name,
                        total: Number(row.totalCents) / 100,
                    })),
                }
            }
            return {
                ok: true,
                ...(result.truncated ? { truncated: true } : {}),
                rows: result.rows.map((row) => ({
                    accountId: row.accountId,
                    name: row.name,
                    currency: row.currency,
                    in: Number(row.inCents) / 100,
                    out: Number(row.outCents) / 100,
                    net: Number(row.netCents) / 100,
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

    // ───── Agent memory ─────
    // Web writes through the v1 endpoints; native writes the synced Drift
    // table. Same ids, same envelopes.
    addMemory: defineTool(toolSchemas.addMemory, async (ctx, args) => {
        const id = newId()
        await ctx.client.mutation(api.v1.memories.mutations.create, {
            id,
            content: args.content,
        })
        return { ok: true, id }
    }),
    updateMemory: defineTool(toolSchemas.updateMemory, async (ctx, args) => {
        await ctx.client.mutation(api.v1.memories.mutations.update, {
            id: args.id,
            content: args.content,
        })
        return { ok: true, id: args.id }
    }),
    forgetMemory: defineTool(toolSchemas.forgetMemory, async (ctx, args) => {
        await ctx.client.mutation(api.v1.memories.mutations.archive, {
            id: args.id,
        })
        return { ok: true, id: args.id }
    }),

    // ───── Settings ─────
    updateSettings: defineTool(
        toolSchemas.updateSettings,
        async (ctx, args) => {
            if (
                args.language === undefined &&
                args.theme === undefined &&
                args.defaultCurrency === undefined
            ) {
                return {
                    ok: false,
                    error: 'Nothing to change — pass language, theme, or defaultCurrency',
                }
            }
            const changed: string[] = []
            if (args.language !== undefined || args.theme !== undefined) {
                if (!ctx.settings) {
                    return {
                        ok: false,
                        error: 'Display settings are not available in this session',
                    }
                }
                if (args.language !== undefined) {
                    ctx.settings.setLanguage(args.language)
                    changed.push(`language=${args.language} (this device only)`)
                }
                if (args.theme !== undefined) {
                    ctx.settings.setTheme(args.theme)
                    changed.push(`theme=${args.theme} (this device only)`)
                }
            }
            if (args.defaultCurrency !== undefined) {
                await ctx.client.mutation(
                    api.v1.users.mutations.updateDefaultCurrency,
                    { currency: args.defaultCurrency.trim().toUpperCase() },
                )
                changed.push(
                    `defaultCurrency=${args.defaultCurrency.trim().toUpperCase()} (account-wide)`,
                )
            }
            return { ok: true, changed }
        },
    ),

    // ───── Math & dates ─────
    calculate: defineTool(toolSchemas.calculate, async (_ctx, args) => {
        try {
            const steps = runCalculate(args.steps)
            return { ok: true, steps, result: steps[steps.length - 1].value }
        } catch (error) {
            return {
                ok: false,
                error: error instanceof Error ? error.message : String(error),
            }
        }
    }),
    calculateDate: defineTool(toolSchemas.calculateDate, async (_ctx, args) => {
        try {
            return { ok: true, ...runCalculateDate(args) }
        } catch (error) {
            return {
                ok: false,
                error: error instanceof Error ? error.message : String(error),
            }
        }
    }),

    // ───── Exchange rates ─────
    getExchangeRate: defineTool(
        toolSchemas.getExchangeRate,
        async (ctx, args) => {
            const from = normalizeCurrencyCode(args.from)
            const to = normalizeCurrencyCode(args.to)
            if (!isValidCurrencyCode(from)) {
                return { ok: false, error: `Unknown currency code: ${from}` }
            }
            if (!isValidCurrencyCode(to)) {
                return { ok: false, error: `Unknown currency code: ${to}` }
            }
            if (from === to) {
                return {
                    ok: false,
                    error: 'from and to are the same currency',
                }
            }
            const snapshot = await ctx.client.query(
                api.v1.exchangeRates.queries.snapshot,
                {},
            )
            if (snapshot.length === 0) {
                return {
                    ok: false,
                    error: 'Exchange rates are unavailable right now',
                }
            }
            const resolution = resolveFxQuote(
                snapshot,
                from,
                to,
                args.market ?? DEFAULT_FX_MARKET,
            )
            if (!resolution) {
                return {
                    ok: false,
                    error: `No exchange rate available for ${from}\u2192${to}`,
                }
            }
            const alternatives = fxAlternatives(snapshot, from, to)
            return {
                ok: true,
                from: resolution.from,
                to: resolution.to,
                market: resolution.market,
                rate: resolution.rate,
                ...(resolution.buy === undefined
                    ? {}
                    : { buy: resolution.buy }),
                ...(resolution.sell === undefined
                    ? {}
                    : { sell: resolution.sell }),
                source: resolution.source,
                asOf: resolution.asOf,
                path: resolution.path,
                ...(isFxQuoteStale(resolution.asOf, Date.now())
                    ? { stale: true }
                    : {}),
                ...(args.amount === undefined
                    ? {}
                    : {
                          converted: convertAmount(
                              args.amount,
                              resolution.rate,
                          ),
                      }),
                ...(Object.keys(alternatives).length > 0
                    ? { alternatives }
                    : {}),
            }
        },
    ),

    // ───── Skills ─────
    readSkill: defineTool(toolSchemas.readSkill, async (_ctx, args) => {
        const skill = AGENT_SKILLS_BY_SLUG.get(args.slug)
        if (!skill) {
            return {
                ok: false,
                error: `Unknown skill: ${args.slug}`,
                availableSlugs: AGENT_SKILLS.map((s) => s.slug),
            }
        }
        return {
            ok: true,
            slug: skill.slug,
            title: skill.title,
            body: skill.body,
        }
    }),
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

/**
 * Carries the value fields to this occurrence and every later one.
 *
 * Only the value fields travel: a date or cadence change is a split, not an
 * update, because the occurrences before this one keep their own spacing.
 * Tags stay per-occurrence for the same reason a date does.
 */
async function updateFuture(
    ctx: { client: import('convex/react').ConvexReactClient },
    args: {
        id: string
        name?: string
        description?: string
        amount?: number
        date?: string
        time?: string
    },
    categoryId: string | undefined,
) {
    if (args.date !== undefined || args.time !== undefined) {
        return {
            ok: false as const,
            error: 'Moving the date of this movement and the ones after it re-anchors the series, so it needs a recurrence argument (it splits the rule in two). To move just this movement, use scope only-this.',
        }
    }
    await ctx.client.mutation(api.v1.recurrences.mutations.updateFuture, {
        transactionId: args.id,
        patch: {
            name: args.name,
            description: args.description,
            amount:
                args.amount !== undefined
                    ? parseAmountToCents(args.amount)
                    : undefined,
            categoryId,
        },
    })
    return { ok: true as const, id: args.id, scope: 'all-future' }
}

/** Re-cadences the series from this occurrence on, by splitting it in two. */
async function splitSeries(
    ctx: { client: import('convex/react').ConvexReactClient },
    args: {
        id: string
        name?: string
        description?: string
        amount?: number
        date?: string
        time?: string
        timeStatus?: 'confirmed' | 'approximation' | 'none'
    },
    recurrence: {
        frequency: 'daily' | 'weekly' | 'monthly' | 'yearly' | 'customDays'
        dayInterval?: bigint
        endDate?: bigint
    },
    categoryId: string | undefined,
) {
    const existing = await ctx.client.query(api.v1.transactions.queries.get, {
        id: args.id,
    })
    if (!existing) return { ok: false as const, error: 'Transaction not found' }

    const existingDate = new Date(Number(existing.date))
    const pad = (n: number) => String(n).padStart(2, '0')
    const dateInput =
        args.date ??
        `${existingDate.getFullYear()}-${pad(
            existingDate.getMonth() + 1,
        )}-${pad(existingDate.getDate())}`
    const timeInput =
        args.time ??
        `${pad(existingDate.getHours())}:${pad(existingDate.getMinutes())}`
    const date = parseTransactionDate(dateInput, 'confirmed', timeInput)

    const recurrenceId = newId()
    const anchorId = await ctx.client.mutation(
        api.v1.recurrences.mutations.splitSeries,
        {
            transactionId: args.id,
            recurrenceId,
            frequency: recurrence.frequency,
            dayInterval: recurrence.dayInterval,
            date,
            dateConfirmed: args.date !== undefined || existing.dateConfirmed,
            timeStatus: args.timeStatus ?? existing.timeStatus,
            patch: {
                name: args.name,
                description: args.description,
                amount:
                    args.amount !== undefined
                        ? parseAmountToCents(args.amount)
                        : undefined,
                categoryId,
            },
        },
    )
    return {
        ok: true as const,
        id: anchorId,
        splitFrom: args.id,
        scope: 'all-future',
        ...(await seriesResult(ctx, recurrenceId, 0n)),
    }
}

/**
 * The recurrence the model asked for, as the mutations want it, or an error
 * string instead — so a payload we cannot interpret is reported rather than
 * silently creating a one-off.
 */
function parseRecurrence(
    recurrence:
        | { frequency: string; dayInterval?: number; endDate?: string }
        | undefined,
):
    | {
          ok: true
          value:
              | {
                    frequency:
                        | 'daily'
                        | 'weekly'
                        | 'monthly'
                        | 'yearly'
                        | 'customDays'
                    dayInterval?: bigint
                    endDate?: bigint
                }
              | undefined
      }
    | { ok: false; error: string } {
    if (recurrence === undefined) return { ok: true, value: undefined }
    const frequency = recurrence.frequency
    if (
        frequency !== 'daily' &&
        frequency !== 'weekly' &&
        frequency !== 'monthly' &&
        frequency !== 'yearly' &&
        frequency !== 'customDays'
    ) {
        return {
            ok: false,
            error: `Unknown recurrence frequency: ${frequency}. Use daily, weekly, monthly, yearly or customDays.`,
        }
    }
    if (
        frequency === 'customDays' &&
        (recurrence.dayInterval === undefined || recurrence.dayInterval < 1)
    ) {
        return {
            ok: false,
            error: 'dayInterval of at least 1 is required for customDays',
        }
    }
    let endDate: bigint | undefined
    if (recurrence.endDate !== undefined) {
        // Inclusive to the end of the day the user named: "hasta el 31" has to
        // include the 31st, and the anchor's clock time is not midnight.
        const day = new Date(Number(parseNaturalDate(recurrence.endDate)))
        endDate = BigInt(
            new Date(
                day.getFullYear(),
                day.getMonth(),
                day.getDate(),
                23,
                59,
                59,
                999,
            ).getTime(),
        )
    }
    return {
        ok: true,
        value: {
            frequency,
            dayInterval:
                frequency === 'customDays'
                    ? BigInt(recurrence.dayInterval ?? 1)
                    : undefined,
            endDate,
        },
    }
}

/**
 * The `recurrence` block a write result carries, so the model can tell the
 * user how many movements it created instead of implying "forever".
 */
async function seriesResult(
    ctx: { client: import('convex/react').ConvexReactClient },
    recurrenceId: string,
    occurrenceIndex: bigint,
) {
    const series = await ctx.client.query(api.v1.recurrences.queries.get, {
        recurrenceId,
        occurrenceIndex,
    })
    return series === null ? {} : { recurrence: serializeSeries(series) }
}

/** The series summary both `getTransaction` and the write results carry. */
function serializeSeries(series: {
    id: string
    frequency: string
    dayInterval?: bigint
    endDate?: bigint
    position: number | null
    total: number | null
    coveredThroughMs: bigint | null
}) {
    return {
        recurrenceId: series.id,
        frequency: series.frequency,
        dayInterval:
            series.dayInterval === undefined
                ? undefined
                : Number(series.dayInterval),
        endDate:
            series.endDate === undefined ? undefined : Number(series.endDate),
        position: series.position,
        total: series.total,
        coveredThrough:
            series.coveredThroughMs === null
                ? null
                : Number(series.coveredThroughMs),
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
