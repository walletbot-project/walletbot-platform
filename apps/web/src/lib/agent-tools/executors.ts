import { api } from '@wallet-bot/backend/api'
import type { ToolName } from '@wallet-bot/shared'
import {
    parseAmountToCents,
    parseOptionalDate,
    parseTransactionDate,
    toolSchemas,
} from '@wallet-bot/shared'
import {
    defineTool,
    resolutionError,
    resolveAccount,
    resolveCategory,
    resolveTag,
    resolveTagIds,
    type ToolExecutor,
} from './helpers'

function newId(): string {
    return crypto.randomUUID()
}

function nativeDashboardOnly() {
    return {
        ok: false,
        error: 'native_only',
        message:
            'Home dashboard filters and widgets are only implemented in the native app right now.',
    }
}

export const toolExecutors = {
    // ───── Accounts ─────
    listAccounts: defineTool(toolSchemas.listAccounts, async (ctx, args) => {
        const accounts = await ctx.client.query(api.accounts.queries.list, {
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
                api.transactions.queries.balance,
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
        await ctx.client.mutation(api.accounts.mutations.create, {
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
        await ctx.client.mutation(api.accounts.mutations.update, {
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
            await ctx.client.mutation(api.accounts.mutations.archive, {
                id: r.entity.id,
            })
            return { ok: true, id: r.entity.id }
        },
    ),

    // ───── Categories ─────
    listCategories: defineTool(toolSchemas.listCategories, async (ctx) => {
        const cats = await ctx.client.query(api.categories.queries.listActive)
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
            await ctx.client.mutation(api.categories.mutations.create, {
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
            await ctx.client.mutation(api.categories.mutations.update, {
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
            await ctx.client.mutation(api.categories.mutations.archive, {
                id: r.entity.id,
            })
            return { ok: true, id: r.entity.id }
        },
    ),

    // ───── Tags ─────
    listTags: defineTool(toolSchemas.listTags, async (ctx) => {
        const tags = await ctx.client.query(api.tags.queries.listActive)
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
        await ctx.client.mutation(api.tags.mutations.create, {
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
        await ctx.client.mutation(api.tags.mutations.update, {
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
        await ctx.client.mutation(api.tags.mutations.archive, {
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
                api.transactions.queries.listPaginated,
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
                        api.transactions.queries.get,
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
            const txn = await ctx.client.query(api.transactions.queries.get, {
                id: args.id,
            })
            if (!txn) return { ok: false, error: 'Transaction not found' }
            return { ok: true, transaction: serializeTransaction(txn) }
        },
    ),
    getRecentTransactions: defineTool(
        toolSchemas.getRecentTransactions,
        async (ctx, args) => {
            const txns = await ctx.client.query(
                api.transactions.queries.recent,
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
        const date = parseTransactionDate(args.date, args.timeStatus)
        await ctx.client.mutation(api.transactions.mutations.createExpense, {
            id,
            name: args.name,
            description: args.description,
            amount: parseAmountToCents(args.amount),
            accountId: accR.entity.id,
            categoryId: catR.entity.id,
            date,
            dateConfirmed: args.dateConfirmed,
            timeStatus: args.timeStatus,
            status: args.status,
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
        const date = parseTransactionDate(args.date, args.timeStatus)
        await ctx.client.mutation(api.transactions.mutations.createIncome, {
            id,
            name: args.name,
            description: args.description,
            amount: parseAmountToCents(args.amount),
            accountId: accR.entity.id,
            categoryId: catR.entity.id,
            date,
            dateConfirmed: args.dateConfirmed,
            timeStatus: args.timeStatus,
            status: args.status,
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
        const date = parseTransactionDate(args.date, args.timeStatus)
        await ctx.client.mutation(api.transactions.mutations.createTransfer, {
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
            dateConfirmed: args.dateConfirmed,
            timeStatus: args.timeStatus,
        })
        await attachTags(ctx, id, args.tagIdsOrNames)
        return { ok: true, id, date: Number(date), timeStatus: args.timeStatus }
    }),
    addBalanceAdjustment: defineTool(
        toolSchemas.addBalanceAdjustment,
        async (ctx, args) => {
            const accR = await resolveAccount(ctx, args.accountIdOrName)
            if (!accR.ok) return resolutionError('Account', accR)
            const id = newId()
            const date = parseTransactionDate(args.date, args.timeStatus)
            await ctx.client.mutation(
                api.transactions.mutations.createBalanceAdjustment,
                {
                    id,
                    accountId: accR.entity.id,
                    balanceAfter: parseAmountToCents(args.balanceAfter),
                    name: args.name,
                    description: args.description,
                    date,
                    dateConfirmed: args.dateConfirmed,
                    timeStatus: args.timeStatus,
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
            const date =
                args.date === undefined
                    ? undefined
                    : parseTransactionDate(args.date, args.timeStatus ?? 'none')
            await ctx.client.mutation(api.transactions.mutations.update, {
                id: args.id,
                name: args.name,
                description: args.description,
                date,
                dateConfirmed: args.dateConfirmed,
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
            await ctx.client.mutation(api.transactions.mutations.archive, {
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
                api.transactions.mutations.tag,
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
                api.transactions.mutations.untag,
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
                api.categories.queries.listActive,
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
            const accounts = await ctx.client.query(api.accounts.queries.list, {
                includeArchived: false,
            })
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

    // ───── Native home dashboard ─────
    listSavedFilters: defineTool(toolSchemas.listSavedFilters, async () =>
        nativeDashboardOnly(),
    ),
    createSavedFilter: defineTool(toolSchemas.createSavedFilter, async () =>
        nativeDashboardOnly(),
    ),
    updateSavedFilter: defineTool(toolSchemas.updateSavedFilter, async () =>
        nativeDashboardOnly(),
    ),
    archiveSavedFilter: defineTool(toolSchemas.archiveSavedFilter, async () =>
        nativeDashboardOnly(),
    ),
    listDashboardWidgets: defineTool(
        toolSchemas.listDashboardWidgets,
        async () => nativeDashboardOnly(),
    ),
    createDashboardWidget: defineTool(
        toolSchemas.createDashboardWidget,
        async () => nativeDashboardOnly(),
    ),
    updateDashboardWidget: defineTool(
        toolSchemas.updateDashboardWidget,
        async () => nativeDashboardOnly(),
    ),
    reorderDashboardWidgets: defineTool(
        toolSchemas.reorderDashboardWidgets,
        async () => nativeDashboardOnly(),
    ),
    archiveDashboardWidget: defineTool(
        toolSchemas.archiveDashboardWidget,
        async () => nativeDashboardOnly(),
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
    await ctx.client.mutation(api.transactions.mutations.tag, {
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
        } = await ctx.client.query(api.transactions.queries.listPaginated, {
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
