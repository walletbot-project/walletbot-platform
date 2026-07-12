import { z } from 'zod'

// Zod schemas (source of truth for tool args)
//
// Conventions:
// - `idOrName` accepts either a UUID or a human name; executors resolve to the
//   underlying entity. On ambiguity the executor returns
//   `{ ok: false, error: "ambiguous", candidates: [...] }`.
// - Amounts are decimal in user-facing units (e.g. 12.50). Executors convert to
//   cents (int64) before persisting.
// - Transaction dates are ISO 8601 strings or natural-language
//   ("today", "yesterday"). The executor parses to ms-epoch and applies the
//   timeStatus contract below.
// - Currency is never an LLM-supplied arg on transactions; it is inferred from
//   the resolved account.

const transactionType = z.enum(['expense', 'income', 'transfer'])
const transactionStatus = z.enum(['pending', 'cleared'])
const transactionTimeStatus = z
    .enum(['confirmed', 'approximation', 'none'])
    .describe(
        'Hour confidence. confirmed when the user states an exact time; approximation when they give a range or event such as morning, lunch, afternoon, dinner, or night; none when they give no time clue. Required on transaction creates.',
    )
const dashboardWidgetType = z.enum(['stat', 'list', 'balance', 'chart'])
const dashboardWidth = z.enum(['full', 'two_thirds', 'half', 'third'])
const statAggregation = z.enum(['sum', 'net', 'count'])
const breakdownGroupBy = z.enum(['category', 'account', 'month'])
const breakdownChartKind = z.enum(['pie', 'bar', 'line'])

const idOrName = z.string().describe('UUID or human name of the entity')
const optionalIdOrName = idOrName.optional()
const isoOrNaturalDate = z
    .string()
    .describe(
        'ISO 8601 date/time or natural language date. Include an exact or estimated time when timeStatus is confirmed or approximation.',
    )
const dateConfirmed = z
    .boolean()
    .describe(
        'Whether the transaction date is certain. Required on every write. true only when the user clearly stated when it happened (an explicit date, or "today"/"hoy", "yesterday"/"ayer"). false when you inferred or guessed it. When in doubt, prefer false.',
    )
const tagList = z
    .array(idOrName)
    .describe(
        'Tag UUIDs or names. Created on the fly if names are unknown? No — must exist.',
    )
const canonicalFilterJson = z
    .string()
    .describe(
        'Canonical saved-filter JSON string: { "combinator": "and"|"or", "not"?: boolean, "children": [...] }. Use fields type, status, date, account, category, tag, currency, amount, text. Omit or use an empty group for all transactions.',
    )
const dashboardBackground = z
    .object({
        mode: z.enum(['none', 'fixed', 'value']),
        fixedColor: z.string().optional().describe('Hex color, e.g. #C8F2D8'),
        low: z.number().optional(),
        high: z.number().optional(),
        lowColor: z.string().optional(),
        betweenColor: z.string().optional(),
        highColor: z.string().optional(),
    })
    .optional()
    .describe(
        'Optional widget background. fixed uses fixedColor. value compares the displayed widget value against low/high and uses lowColor/betweenColor/highColor.',
    )

export const toolSchemas = {
    // ───── Accounts ─────
    listAccounts: z.object({
        includeArchived: z
            .boolean()
            .optional()
            .describe('Include archived accounts. Defaults to false.'),
    }),
    getAccount: z.object({
        idOrName: idOrName,
    }),
    getAccountBalance: z.object({
        idOrName: idOrName,
    }),
    createAccount: z.object({
        name: z.string().describe('Display name (e.g. "BBVA", "Efectivo")'),
        currency: z
            .string()
            .describe('ISO 4217 currency code (e.g. "ARS", "USD"). Immutable.'),
        color: z
            .string()
            .optional()
            .describe(
                'Hex color (e.g. "#4F46E5"). Optional — a sensible default is applied. Only set it if the user explicitly states a color. Never ask the user for it.',
            ),
        icon: z
            .string()
            .optional()
            .describe(
                'Icon name. Optional — a sensible default is applied. Only set it if the user explicitly names an icon. Never ask the user for it.',
            ),
        description: z.string().optional(),
    }),
    updateAccount: z.object({
        idOrName: idOrName,
        name: z.string().optional(),
        color: z.string().optional(),
        icon: z.string().optional(),
        description: z.string().optional(),
    }),
    archiveAccount: z.object({
        idOrName: idOrName,
    }),

    // ───── Categories ─────
    listCategories: z.object({
        includeArchived: z.boolean().optional(),
    }),
    getCategory: z.object({
        idOrName: idOrName,
    }),
    createCategory: z.object({
        name: z.string(),
        color: z
            .string()
            .optional()
            .describe(
                'Hex color (e.g. "#4F46E5"). Optional — a sensible default is applied. Only set it if the user explicitly states a color. Never ask the user for it.',
            ),
        icon: z
            .string()
            .optional()
            .describe(
                'Icon name. Optional — a sensible default is applied. Only set it if the user explicitly names an icon. Never ask the user for it.',
            ),
        description: z.string().optional(),
    }),
    updateCategory: z.object({
        idOrName: idOrName,
        name: z.string().optional(),
        color: z.string().optional(),
        icon: z.string().optional(),
        description: z.string().optional(),
    }),
    archiveCategory: z.object({
        idOrName: idOrName,
    }),

    // ───── Tags ─────
    listTags: z.object({
        includeArchived: z.boolean().optional(),
    }),
    getTag: z.object({
        idOrName: idOrName,
    }),
    createTag: z.object({
        name: z.string(),
        parentIdOrName: optionalIdOrName,
        color: z
            .string()
            .optional()
            .describe(
                'Hex color (e.g. "#4F46E5"). Optional — a sensible default is applied. Only set it if the user explicitly states a color. Never ask the user for it.',
            ),
        description: z.string().optional(),
    }),
    updateTag: z.object({
        idOrName: idOrName,
        name: z.string().optional(),
        parentIdOrName: optionalIdOrName,
        color: z.string().optional(),
        description: z.string().optional(),
    }),
    archiveTag: z.object({
        idOrName: idOrName,
    }),

    // ───── Transactions: read ─────
    listTransactions: z.object({
        type: transactionType.optional(),
        accountIdOrName: optionalIdOrName,
        categoryIdOrName: optionalIdOrName,
        tagIdOrName: optionalIdOrName,
        status: transactionStatus.optional(),
        dateFrom: isoOrNaturalDate.optional(),
        dateTo: isoOrNaturalDate.optional(),
        limit: z
            .number()
            .int()
            .optional()
            .describe('Max results. Defaults to 50.'),
    }),
    getTransaction: z.object({
        id: z.string().describe('Transaction UUID'),
    }),
    getRecentTransactions: z.object({
        limit: z.number().int().optional().describe('Defaults to 10'),
    }),

    // ───── Transactions: write (split per type) ─────
    addExpense: z.object({
        amount: z.number().describe('Decimal amount (e.g. 12.50)'),
        accountIdOrName: idOrName,
        categoryIdOrName: idOrName,
        name: z.string().describe('Short label (e.g. "Starbucks")'),
        date: isoOrNaturalDate.optional(),
        dateConfirmed,
        timeStatus: transactionTimeStatus,
        description: z.string().optional(),
        tagIdsOrNames: tagList.optional(),
        status: transactionStatus.optional(),
    }),
    addIncome: z.object({
        amount: z.number(),
        accountIdOrName: idOrName,
        categoryIdOrName: idOrName,
        name: z.string(),
        date: isoOrNaturalDate.optional(),
        dateConfirmed,
        timeStatus: transactionTimeStatus,
        description: z.string().optional(),
        tagIdsOrNames: tagList.optional(),
        status: transactionStatus.optional(),
    }),
    addTransfer: z.object({
        amount: z.number().describe('Amount taken from source account'),
        fromAccountIdOrName: idOrName,
        toAccountIdOrName: idOrName,
        toAmount: z
            .number()
            .optional()
            .describe(
                'Amount received on the destination account if different (cross-currency)',
            ),
        exchangeRate: z.number().optional(),
        name: z.string(),
        categoryIdOrName: optionalIdOrName,
        date: isoOrNaturalDate.optional(),
        dateConfirmed,
        timeStatus: transactionTimeStatus,
        description: z.string().optional(),
        tagIdsOrNames: tagList.optional(),
    }),
    addBalanceAdjustment: z.object({
        accountIdOrName: idOrName,
        balanceAfter: z
            .number()
            .describe(
                'Final observed balance after the adjustment, in user units. Sacred: this is what the user actually counted.',
            ),
        name: z.string().optional(),
        date: isoOrNaturalDate.optional(),
        dateConfirmed,
        timeStatus: transactionTimeStatus,
        description: z.string().optional(),
    }),
    updateTransaction: z.object({
        id: z.string(),
        name: z.string().optional(),
        description: z.string().optional(),
        date: isoOrNaturalDate.optional(),
        dateConfirmed,
        timeStatus: transactionTimeStatus
            .optional()
            .describe(
                'Required when changing date/time; omit when the transaction time is unchanged.',
            ),
        amount: z.number().optional(),
        categoryIdOrName: optionalIdOrName,
        status: transactionStatus.optional(),
    }),
    deleteTransaction: z.object({
        id: z.string(),
    }),
    tagTransaction: z.object({
        transactionId: z.string(),
        tagIdsOrNames: tagList,
    }),
    untagTransaction: z.object({
        transactionId: z.string(),
        tagIdsOrNames: tagList,
    }),

    // ───── Summaries ─────
    summarizeByCategory: z.object({
        dateFrom: isoOrNaturalDate,
        dateTo: isoOrNaturalDate,
        type: transactionType.optional(),
        currency: z.string().optional(),
    }),
    summarizeByAccount: z.object({
        dateFrom: isoOrNaturalDate,
        dateTo: isoOrNaturalDate,
    }),

    // ───── Dashboard saved filters ─────
    listSavedFilters: z.object({}),
    createSavedFilter: z.object({
        name: z.string(),
        filterConfigJson: canonicalFilterJson,
    }),
    updateSavedFilter: z.object({
        id: z.string(),
        name: z.string().optional(),
        filterConfigJson: canonicalFilterJson.optional(),
    }),
    archiveSavedFilter: z.object({
        id: z.string(),
    }),

    // ───── Home dashboard widgets (native-only v1) ─────
    listDashboardWidgets: z.object({}),
    createDashboardWidget: z.object({
        type: dashboardWidgetType,
        title: z.string(),
        width: dashboardWidth.optional(),
        filterConfigJson: canonicalFilterJson.optional(),
        aggregation: statAggregation.optional(),
        limit: z.number().int().optional(),
        currency: z.string().optional(),
        groupBy: breakdownGroupBy.optional(),
        chartKind: breakdownChartKind.optional(),
        background: dashboardBackground,
    }),
    updateDashboardWidget: z.object({
        id: z.string(),
        type: dashboardWidgetType.optional(),
        title: z.string().optional(),
        width: dashboardWidth.optional(),
        filterConfigJson: canonicalFilterJson.optional(),
        aggregation: statAggregation.optional(),
        limit: z.number().int().optional(),
        currency: z.string().optional(),
        groupBy: breakdownGroupBy.optional(),
        chartKind: breakdownChartKind.optional(),
        background: dashboardBackground,
    }),
    reorderDashboardWidgets: z.object({
        ids: z
            .array(z.string())
            .describe('Dashboard widget ids in display order.'),
    }),
    archiveDashboardWidget: z.object({
        id: z.string(),
    }),
} satisfies Record<string, z.ZodType>
