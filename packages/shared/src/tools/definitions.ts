import { z } from 'zod'
import { DATE_CALC_OPERATIONS, DATE_CALC_UNITS } from './date-calc'
import { FX_MARKETS } from './fx'

// Zod schemas (source of truth for tool args)
//
// Conventions:
// - `idOrName` accepts either a UUID or a human name; executors resolve to the
//   underlying entity. On failure the executor returns
//   `{ ok: false, error: "<Entity> not found" }`, and on a name matching more
//   than one entity `{ ok: false, error: "<Entity> is ambiguous", candidates }`.
// - Amounts are decimal in user-facing display units (e.g. 12.50). Executors
//   convert to cents (int64) before persisting.
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
const transactionTime = z
    .string()
    .optional()
    .describe(
        'Transaction clock in 24-hour HH:mm format. REQUIRED whenever timeStatus is confirmed or approximation — the create is rejected without it, so never omit it for those. For confirmed, use the exact time stated. For approximation, map the part-of-day cue to its representative clock: morning/desayuno/mañana = 10:00; lunch/almuerzo/mediodía = 13:00; afternoon/merienda/tarde = 16:00; dinner/cena/noche = 22:00; madrugada = 02:00. Leave it empty only when timeStatus is none. It is independent from date and may be supplied when date is omitted.',
    )
const dashboardWidgetType = z.enum(['stat', 'list', 'balance', 'chart'])
const dashboardWidth = z.enum(['full', 'two_thirds', 'half', 'third'])
const statAggregation = z.enum(['sum', 'net', 'count'])
const breakdownGroupBy = z.enum(['category', 'account', 'month'])
const breakdownChartKind = z.enum(['pie', 'bar', 'line'])
const summaryGroupBy = z.enum(['category', 'account'])

const idOrName = z.string().describe('UUID or human name of the entity')
const optionalIdOrName = idOrName.optional()
const isoOrNaturalDate = z
    .string()
    .describe(
        'ISO 8601 or natural-language calendar date, including deterministic relative dates such as "el jueves pasado". Use the separate time argument for the clock.',
    )
const dateConfirmed = z
    .boolean()
    .describe(
        'Whether the calendar day is certain. true when date comes from an explicit or deterministic relative day; false when date is omitted and today is only the default. Executors enforce this from date presence.',
    )
const tagList = z
    .array(idOrName)
    .describe(
        'Tag UUIDs or names. Tags must already exist — unknown names are skipped and reported back in `missing`, never created on the fly.',
    )
const canonicalFilterJson = z
    .string()
    .describe(
        'Canonical saved-filter JSON string: { "combinator": "and"|"or", "not"?: boolean, "children": [...] }. Use fields type, status, date, account, category, tag, currency, amount, text. Omit or use an empty group for all transactions. Amount values inside filter JSON are stored in cents.',
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
        'Optional widget background. fixed uses fixedColor. value compares the displayed widget value against low/high (in display units) and uses lowColor/betweenColor/highColor.',
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
            .optional()
            .describe(
                'ISO 4217 currency code (e.g. "ARS", "USD"). Immutable once set. Optional — omit it if the user does not specify one; the user\'s default currency is applied.',
            ),
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
        includeArchived: z
            .boolean()
            .optional()
            .describe('Include archived categories. Defaults to false.'),
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
        includeArchived: z
            .boolean()
            .optional()
            .describe('Include archived tags. Defaults to false.'),
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
            .describe(
                'Max results. Defaults to 10 when no filters are given (recent movements), 50 otherwise.',
            ),
    }),
    getTransaction: z.object({
        id: z.string().describe('Transaction UUID'),
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
        time: transactionTime,
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
        time: transactionTime,
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
        exchangeRate: z
            .number()
            .optional()
            .describe(
                'Optional reference metadata only — it never derives toAmount. Cross-currency transfers still require toAmount.',
            ),
        name: z.string(),
        categoryIdOrName: optionalIdOrName.describe(
            'Optional. Transfers are excluded from category breakdowns, so omit it unless the user names one.',
        ),
        date: isoOrNaturalDate.optional(),
        dateConfirmed,
        timeStatus: transactionTimeStatus,
        time: transactionTime,
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
        time: transactionTime,
        description: z.string().optional(),
    }),
    updateTransaction: z.object({
        id: z.string(),
        name: z.string().optional(),
        description: z.string().optional(),
        date: isoOrNaturalDate.optional(),
        dateConfirmed: dateConfirmed.optional(),
        timeStatus: transactionTimeStatus
            .optional()
            .describe(
                'Required when changing date/time; omit when the transaction time is unchanged.',
            ),
        time: transactionTime,
        amount: z.number().optional(),
        categoryIdOrName: optionalIdOrName,
        status: transactionStatus.optional(),
        addTagIdsOrNames: tagList
            .optional()
            .describe(
                'Tags to attach. Tag UUIDs or names; unknown names are skipped and reported in `missing`.',
            ),
        removeTagIdsOrNames: tagList
            .optional()
            .describe(
                'Tags to detach. Tag UUIDs or names; unknown names are skipped and reported in `missing`.',
            ),
    }),
    deleteTransaction: z.object({
        id: z.string(),
    }),

    // ───── Summaries ─────
    summarizeTransactions: z.object({
        groupBy: summaryGroupBy.describe(
            'category: totals per category (transfers excluded). account: per-account money-in/money-out/net flows.',
        ),
        dateFrom: isoOrNaturalDate,
        dateTo: isoOrNaturalDate,
        type: transactionType
            .optional()
            .describe('Only meaningful with groupBy category.'),
        currency: z
            .string()
            .optional()
            .describe(
                'Only meaningful with groupBy category: restrict the totals to one currency. Without it, amounts across currencies are added together as raw numbers.',
            ),
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

    // ───── Home dashboard widgets ─────
    listDashboardWidgets: z.object({}),
    createDashboardWidget: z.object({
        type: dashboardWidgetType,
        title: z.string(),
        width: dashboardWidth.optional(),
        filterConfigJson: canonicalFilterJson.optional(),
        aggregation: statAggregation.optional(),
        limit: z.number().int().optional(),
        currency: z.string().optional(),
        accountIds: z
            .array(z.string())
            .optional()
            .describe(
                'Balance widgets: the account ids to sum, all within `currency`. Omit or pass an empty list for every account in that currency.',
            ),
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
        accountIds: z
            .array(z.string())
            .optional()
            .describe(
                'Balance widgets: the account ids to sum, all within `currency`. Omit or pass an empty list for every account in that currency.',
            ),
        groupBy: breakdownGroupBy.optional(),
        chartKind: breakdownChartKind.optional(),
        background: dashboardBackground,
    }),
    reorderDashboardWidgets: z.object({
        ids: z
            .array(z.string())
            .describe(
                'ALL live dashboard widget ids in the desired display order — a partial list silently skips the missing ones.',
            ),
    }),
    archiveDashboardWidget: z.object({
        id: z.string(),
    }),

    // ───── Agent memory ─────
    addMemory: z.object({
        content: z
            .string()
            .describe(
                'One durable fact or preference, self-contained and concise (e.g. "If no account is stated, use Galicia."). Never secrets, never one-off transaction details.',
            ),
    }),
    updateMemory: z.object({
        id: z
            .string()
            .describe(
                'Memory id, from the Memories block in your instructions or a previous memory tool result.',
            ),
        content: z.string().describe('The full replacement text.'),
    }),
    forgetMemory: z.object({
        id: z
            .string()
            .describe(
                'Memory id, from the Memories block in your instructions or a previous memory tool result.',
            ),
    }),

    // ───── Settings ─────
    updateSettings: z.object({
        language: z
            .enum(['system', 'es', 'en'])
            .optional()
            .describe(
                'Display language preference. Applies to THIS device only.',
            ),
        theme: z
            .enum(['system', 'light', 'dark'])
            .optional()
            .describe('Theme preference. Applies to THIS device only.'),
        defaultCurrency: z
            .string()
            .optional()
            .describe(
                'ISO 4217 code (e.g. "ARS"). Account-wide — applies on every device.',
            ),
    }),

    // ───── Math & dates ─────
    calculate: z.object({
        steps: z
            .array(
                z.object({
                    expression: z
                        .string()
                        .describe(
                            'One math expression, e.g. "1200 * 0.21" or "total / 3". Allowed: numbers, + - * / ^, parentheses, names bound by earlier steps, and the functions abs, ceil, floor, max, min, pow, round (round(x) or round(x, digits)), sqrt. Multiplication must be explicit (2 * x, never 2x). No percent sign — write 21% as 0.21.',
                        ),
                    name: z
                        .string()
                        .optional()
                        .describe(
                            'Optional variable name binding this step result for use in later steps (e.g. "total").',
                        ),
                }),
            )
            .min(1)
            .max(20)
            .describe(
                'Ordered calculation steps. Later steps can reference the names bound by earlier ones.',
            ),
    }),
    calculateDate: z.object({
        operation: z
            .enum(DATE_CALC_OPERATIONS)
            .describe(
                'add/subtract: move date by amount × unit. diff: whole units from date to otherDate (signed). startOf/endOf: the period boundary containing date. dayOfWeek: name the weekday of date.',
            ),
        date: isoOrNaturalDate.describe(
            'Base date: ISO 8601 or natural language ("today", "hoy", "el jueves pasado").',
        ),
        amount: z
            .number()
            .int()
            .optional()
            .describe('Whole number of units. Required for add and subtract.'),
        unit: z
            .enum(DATE_CALC_UNITS)
            .optional()
            .describe(
                'Required for add, subtract and diff. For startOf/endOf: week, month or year (weeks run Monday–Sunday).',
            ),
        otherDate: z
            .string()
            .optional()
            .describe(
                'Required for diff: the end date, same formats as date. The result is positive when otherDate is after date.',
            ),
    }),

    // ───── Exchange rates ─────
    getExchangeRate: z.object({
        from: z
            .string()
            .describe(
                'ISO 4217 code of the currency being converted FROM, e.g. "USD".',
            ),
        to: z
            .string()
            .describe(
                'ISO 4217 code of the currency being converted TO, e.g. "ARS".',
            ),
        amount: z
            .number()
            .optional()
            .describe(
                'Optional amount expressed in `from`. When present the result adds `converted`, so there is no need to call calculate afterwards.',
            ),
        market: z
            .enum(FX_MARKETS)
            .optional()
            .describe(
                'Which quote to use. Defaults to official. Argentina publishes several prices for the same pair: official (bank / home banking), blue (informal cash), mep and ccl (through securities), card (purchases abroad — the surcharge is already inside the number), crypto (stablecoins), wholesale (interbank, not a retail price). Only ARS pairs carry more than one; any other pair falls back to official and says so in the result.',
            ),
    }),

    // ───── Skills ─────
    readSkill: z.object({
        slug: z
            .string()
            .describe(
                'A skill slug from the skills index in your instructions.',
            ),
    }),
} satisfies Record<string, z.ZodType>
