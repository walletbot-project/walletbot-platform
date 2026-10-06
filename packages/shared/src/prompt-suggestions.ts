/**
 * Per-user prompt suggestions for the empty Gasti screen.
 *
 * Built on the client from the active accounts, categories, tags and the
 * latest movements, with a new draw on every open. The Dart port is
 * apps/native/lib/voice/prompt_suggestions.dart. Both run the fixture table in
 * prompt-suggestions-fixtures.json, so the seeded random source, the draw
 * order and the tie-breaks have to stay identical on both sides.
 */
export type PromptSuggestionKind =
    | 'logExpense'
    | 'spentInCategoryThisMonth'
    | 'accountBalance'
    | 'topSpendingThisMonth'
    | 'compareCategoryLastMonth'
    | 'transfer'
    | 'logIncome'
    | 'spentWithTag'
    | 'recentExpenses'
    | 'whatCanYouDo'
    | 'createCashAccount'
    | 'setupCategories'
    | 'howToLogExpense'
    | 'homeWidget'

export type PromptSuggestion = {
    kind: PromptSuggestionKind
    category?: string
    account?: string
    toAccount?: string
    tag?: string
    amountCents?: number
}

export type SuggestionAccount = { id: string; name: string; currency: string }
export type SuggestionCategory = { id: string; name: string }
export type SuggestionTag = { name: string; usageCount: number }
export type SuggestionMovement = {
    type: string
    amountCents: number
    currency: string
    accountId: string
    categoryId: string
    toAccountId?: string | null
}

export type SuggestionData = {
    accounts: SuggestionAccount[]
    categories: SuggestionCategory[]
    tags: SuggestionTag[]
    /** Newest first. */
    movements: SuggestionMovement[]
}

export const PROMPT_SUGGESTION_COUNT = 5
/** Every draw keeps one slot for a Home widget suggestion. */
const DRAWN_COUNT = PROMPT_SUGGESTION_COUNT - 1
export const PROMPT_SUGGESTION_MOVEMENTS_CAP = 50
const MAX_USES_PER_CATEGORY = 2
const REDRAW_ATTEMPTS = 6

const KIND_WEIGHTS: [PromptSuggestionKind, number][] = [
    ['logExpense', 3],
    ['spentInCategoryThisMonth', 3],
    ['accountBalance', 2],
    ['topSpendingThisMonth', 2],
    ['compareCategoryLastMonth', 1],
    ['transfer', 1],
    ['logIncome', 1],
    ['spentWithTag', 1],
    ['recentExpenses', 1],
]

const ACTION_KINDS = new Set<PromptSuggestionKind>([
    'logExpense',
    'transfer',
    'logIncome',
])

const STARTER_KINDS: PromptSuggestionKind[] = [
    'whatCanYouDo',
    'createCashAccount',
    'setupCategories',
    'howToLogExpense',
]

/** Seeded uniform [0, 1) source, ported bit for bit to Dart. */
export function mulberry32(seed: number): () => number {
    let a = seed >>> 0
    return () => {
        a = (a + 0x6d2b79f5) >>> 0
        let t = Math.imul(a ^ (a >>> 15), 1 | a) >>> 0
        t = (((t + Math.imul(t ^ (t >>> 7), 61 | t)) >>> 0) ^ t) >>> 0
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
}

export function promptSuggestionKey(s: PromptSuggestion): string {
    return [
        s.kind,
        s.category ?? '',
        s.account ?? '',
        s.toAccount ?? '',
        s.tag ?? '',
        s.amountCents?.toString() ?? '',
    ].join('|')
}

export function promptSuggestionSetKey(suggestions: PromptSuggestion[]) {
    return suggestions.map(promptSuggestionKey).sort().join('\n')
}

let lastShown = ''

/**
 * The suggestions for one open of the screen. Never the exact set shown on
 * the previous open, unless the user's data only allows one set.
 */
export function nextPromptSuggestions(
    data: SuggestionData,
    random: () => number = mulberry32(Math.floor(Math.random() * 2 ** 32)),
): PromptSuggestion[] {
    const suggestions = generatePromptSuggestions(data, {
        random,
        previous: lastShown,
    })
    lastShown = promptSuggestionSetKey(suggestions)
    return suggestions
}

export function generatePromptSuggestions(
    data: SuggestionData,
    { random, previous }: { random: () => number; previous?: string },
): PromptSuggestion[] {
    const stats = buildStats(data)
    if (
        stats.expenses.length === 0 &&
        stats.incomes.length === 0 &&
        stats.transfers.length === 0
    ) {
        const starters = shuffle(
            STARTER_KINDS.map((kind): PromptSuggestion => ({ kind })),
            random,
        ).slice(0, DRAWN_COUNT)
        return shuffle([...starters, { kind: 'homeWidget' }], random)
    }
    let drawn: PromptSuggestion[] = []
    for (let attempt = 0; attempt < REDRAW_ATTEMPTS; attempt++) {
        drawn = draw(stats, random)
        if (promptSuggestionSetKey(drawn) !== previous) break
    }
    return drawn
}

/**
 * Amounts are suggestions to edit, not records: two significant digits, in
 * integer cents so both languages agree (3487 → 3500, 34.87 → 35).
 */
export function niceAmountCents(cents: number): number {
    const value = Math.abs(cents)
    const digits = value.toString().length
    if (digits <= 2) return value
    const step = 10 ** (digits - 2)
    return Math.floor((value + step / 2) / step) * step
}

type Expense = { categoryId: string; accountId: string; cents: number }

type Stats = {
    data: SuggestionData
    accountsById: Map<string, SuggestionAccount>
    categoryNames: Map<string, string>
    accountUses: Map<string, number>
    categoryUses: Map<string, number>
    expenses: Expense[]
    incomes: SuggestionMovement[]
    transfers: SuggestionMovement[]
    usedTags: SuggestionTag[]
    sameCurrencyAccounts: Map<string, SuggestionAccount[]>
}

function increment(map: Map<string, number>, key: string) {
    map.set(key, (map.get(key) ?? 0) + 1)
}

function buildStats(data: SuggestionData): Stats {
    const accountsById = new Map(data.accounts.map((a) => [a.id, a]))
    const categoryNames = new Map(data.categories.map((c) => [c.id, c.name]))
    const accountUses = new Map<string, number>()
    const expenses: Expense[] = []
    const incomes: SuggestionMovement[] = []
    const transfers: SuggestionMovement[] = []
    for (const m of data.movements) {
        if (accountsById.has(m.accountId)) increment(accountUses, m.accountId)
        if (m.type === 'expense') {
            if (
                categoryNames.has(m.categoryId) &&
                accountsById.has(m.accountId)
            ) {
                expenses.push({
                    categoryId: m.categoryId,
                    accountId: m.accountId,
                    cents: Math.abs(m.amountCents),
                })
            }
        } else if (m.type === 'income') {
            if (accountsById.has(m.accountId)) incomes.push(m)
        } else if (m.type === 'transfer') {
            const to = m.toAccountId
            if (
                to &&
                to !== m.accountId &&
                accountsById.has(m.accountId) &&
                accountsById.has(to)
            ) {
                transfers.push(m)
                increment(accountUses, to)
            }
        }
    }
    const categoryUses = new Map<string, number>()
    for (const e of expenses) increment(categoryUses, e.categoryId)
    const sameCurrencyAccounts = new Map<string, SuggestionAccount[]>()
    for (const a of data.accounts) {
        const group = sameCurrencyAccounts.get(a.currency) ?? []
        group.push(a)
        sameCurrencyAccounts.set(a.currency, group)
    }
    for (const [currency, group] of [...sameCurrencyAccounts]) {
        if (group.length < 2) sameCurrencyAccounts.delete(currency)
    }
    return {
        data,
        accountsById,
        categoryNames,
        accountUses,
        categoryUses,
        expenses,
        incomes,
        transfers,
        usedTags: data.tags.filter((t) => t.usageCount > 0),
        sameCurrencyAccounts,
    }
}

function transferCurrencies(stats: Stats): string[] {
    return [...stats.sameCurrencyAccounts.keys()].filter((currency) =>
        stats.expenses.some(
            (e) => stats.accountsById.get(e.accountId)?.currency === currency,
        ),
    )
}

function applies(kind: PromptSuggestionKind, stats: Stats): boolean {
    switch (kind) {
        case 'logExpense':
        case 'spentInCategoryThisMonth':
        case 'compareCategoryLastMonth':
        case 'recentExpenses':
            return stats.expenses.length > 0
        case 'accountBalance':
            return stats.data.accounts.length > 0
        case 'topSpendingThisMonth':
            return stats.expenses.length >= 5
        case 'transfer':
            return (
                stats.transfers.length > 0 ||
                transferCurrencies(stats).length > 0
            )
        case 'logIncome':
            return stats.incomes.length > 0
        case 'spentWithTag':
            return stats.usedTags.length > 0
        default:
            return false
    }
}

function draw(stats: Stats, random: () => number): PromptSuggestion[] {
    const weights = new Map(KIND_WEIGHTS)
    const pool = KIND_WEIGHTS.map(([kind]) => kind).filter((kind) =>
        applies(kind, stats),
    )
    const categoryUses = new Map<string, number>()
    const drawn: PromptSuggestion[] = []

    const takeOne = (where: (kind: PromptSuggestionKind) => boolean) => {
        while (drawn.length < DRAWN_COUNT) {
            const candidates = pool.filter(where)
            if (candidates.length === 0) return
            const kind = weightedPick(
                candidates,
                (k) => weights.get(k) ?? 0,
                random,
            )
            pool.splice(pool.indexOf(kind), 1)
            const suggestion = build(kind, stats, random, categoryUses)
            if (suggestion) {
                drawn.push(suggestion)
                return
            }
        }
    }

    takeOne((k) => ACTION_KINDS.has(k))
    takeOne((k) => !ACTION_KINDS.has(k))
    while (drawn.length < DRAWN_COUNT && pool.length > 0) {
        takeOne(() => true)
    }
    const widget = build('homeWidget', stats, random, categoryUses)
    if (widget) drawn.push(widget)
    return shuffle(drawn, random)
}

function build(
    kind: PromptSuggestionKind,
    stats: Stats,
    random: () => number,
    categoryUses: Map<string, number>,
): PromptSuggestion | null {
    const pickCategory = (): string | null => {
        const candidates = [...stats.categoryUses.keys()].filter(
            (id) => (categoryUses.get(id) ?? 0) < MAX_USES_PER_CATEGORY,
        )
        if (candidates.length === 0) return null
        const id = weightedPick(
            candidates,
            (id) => stats.categoryUses.get(id) ?? 0,
            random,
        )
        increment(categoryUses, id)
        return id
    }

    switch (kind) {
        case 'logExpense': {
            const categoryId = pickCategory()
            if (categoryId === null) return null
            const expenses = stats.expenses.filter(
                (e) => e.categoryId === categoryId,
            )
            const account =
                stats.data.accounts.length >= 2
                    ? stats.accountsById.get(
                          mostFrequent(expenses.map((e) => e.accountId)),
                      )
                    : undefined
            return {
                kind,
                category: stats.categoryNames.get(categoryId),
                account: account?.name,
                amountCents: niceAmountCents(
                    median(expenses.map((e) => e.cents)),
                ),
            }
        }
        case 'spentInCategoryThisMonth':
        case 'compareCategoryLastMonth': {
            const categoryId = pickCategory()
            if (categoryId === null) return null
            return { kind, category: stats.categoryNames.get(categoryId) }
        }
        case 'accountBalance': {
            const account = weightedPick(
                stats.data.accounts,
                (a) => (stats.accountUses.get(a.id) ?? 0) + 1,
                random,
            )
            return { kind, account: account.name }
        }
        case 'transfer':
            return buildTransfer(stats, random)
        case 'logIncome': {
            const accountIds = [
                ...new Set(stats.incomes.map((m) => m.accountId)),
            ]
            const accountId = weightedPick(
                accountIds,
                (id) => stats.incomes.filter((m) => m.accountId === id).length,
                random,
            )
            return {
                kind,
                account: stats.accountsById.get(accountId)?.name,
                amountCents: niceAmountCents(
                    median(
                        stats.incomes
                            .filter((m) => m.accountId === accountId)
                            .map((m) => Math.abs(m.amountCents)),
                    ),
                ),
            }
        }
        case 'spentWithTag': {
            const tag = weightedPick(
                stats.usedTags,
                (t) => t.usageCount,
                random,
            )
            return { kind, tag: tag.name }
        }
        case 'topSpendingThisMonth':
        case 'recentExpenses':
            return { kind }
        case 'homeWidget': {
            const categoryId = pickCategory()
            return categoryId === null
                ? { kind }
                : { kind, category: stats.categoryNames.get(categoryId) }
        }
        default:
            return null
    }
}

function buildTransfer(
    stats: Stats,
    random: () => number,
): PromptSuggestion | null {
    if (stats.transfers.length > 0) {
        const transfer =
            stats.transfers[Math.floor(random() * stats.transfers.length)]
        const pair = stats.transfers.filter(
            (m) =>
                m.accountId === transfer.accountId &&
                m.toAccountId === transfer.toAccountId,
        )
        return {
            kind: 'transfer',
            account: stats.accountsById.get(transfer.accountId)?.name,
            toAccount: stats.accountsById.get(transfer.toAccountId ?? '')?.name,
            amountCents: niceAmountCents(
                median(pair.map((m) => Math.abs(m.amountCents))),
            ),
        }
    }
    const currencies = transferCurrencies(stats)
    if (currencies.length === 0) return null
    const currency = currencies[Math.floor(random() * currencies.length)]
    const accounts = [...(stats.sameCurrencyAccounts.get(currency) ?? [])]
    const weight = (a: SuggestionAccount) =>
        (stats.accountUses.get(a.id) ?? 0) + 1
    const from = weightedPick(accounts, weight, random)
    accounts.splice(accounts.indexOf(from), 1)
    const to = weightedPick(accounts, weight, random)
    return {
        kind: 'transfer',
        account: from.name,
        toAccount: to.name,
        amountCents: niceAmountCents(
            median(
                stats.expenses
                    .filter(
                        (e) =>
                            stats.accountsById.get(e.accountId)?.currency ===
                            currency,
                    )
                    .map((e) => e.cents),
            ),
        ),
    }
}

function weightedPick<T>(
    items: T[],
    weight: (item: T) => number,
    random: () => number,
): T {
    const total = items.reduce((sum, item) => sum + weight(item), 0)
    let target = random() * total
    for (const item of items) {
        target -= weight(item)
        if (target < 0) return item
    }
    return items[items.length - 1]
}

function shuffle<T>(items: T[], random: () => number): T[] {
    const result = [...items]
    for (let i = result.length - 1; i > 0; i--) {
        const j = Math.floor(random() * (i + 1))
        ;[result[i], result[j]] = [result[j], result[i]]
    }
    return result
}

function median(values: number[]): number {
    const sorted = [...values].sort((a, b) => a - b)
    return sorted[Math.floor((sorted.length - 1) / 2)]
}

function mostFrequent(values: string[]): string {
    const counts = new Map<string, number>()
    for (const value of values) increment(counts, value)
    let best = values[0]
    for (const [value, count] of counts) {
        if (count > (counts.get(best) ?? 0)) best = value
    }
    return best
}
