// The user-context payload each client builds from its own source of truth
// (native from Drift, web from its Convex queries) and sends alongside the
// live-token mint request. The server never reads the database for it: it
// sanitizes the payload (caps below) and interpolates it into the system
// prompt as the USER_CONTEXT block.
//
// The caps are abuse prevention, not sizing guidance — they are far above
// what the clients send. Mirrored to Dart by the agent codegen
// (`pnpm run generate:agent`).

export const AGENT_CONTEXT_CAPS = {
    accounts: 100,
    categories: 200,
    tags: 200,
    recentTransactions: 50,
    memories: 200,
    /** Hard cap on the rendered USER_CONTEXT block, in UTF-16 code units. */
    maxSerializedChars: 32 * 1024,
} as const

export type AgentContextAccount = {
    id: string
    name: string
    currency: string
    isArchived?: boolean
}

export type AgentContextCategory = {
    id: string
    name: string
}

export type AgentContextTag = {
    id: string
    name: string
    parentId?: string
}

export type AgentContextTransaction = {
    name: string
    amount: number
    currency: string
    type: string
    account?: string
    category?: string
    /** Local calendar date/time of the movement, e.g. "2026-08-23 14:30". */
    date: string
}

export type AgentContextMemory = {
    id: string
    content: string
}

export type AgentContextSettings = {
    defaultCurrency?: string
    /** Device-scoped display language preference: 'system' | 'es' | 'en'. */
    language?: string
    /** Device-scoped theme preference: 'system' | 'light' | 'dark'. */
    theme?: string
}

export type AgentUserContext = {
    userName?: string
    userEmail?: string
    settings?: AgentContextSettings
    accounts?: AgentContextAccount[]
    categories?: AgentContextCategory[]
    tags?: AgentContextTag[]
    recentTransactions?: AgentContextTransaction[]
    memories?: AgentContextMemory[]
}

const MAX_FIELD_CHARS = 500

function asBoundedString(value: unknown): string | undefined {
    if (typeof value !== 'string') return undefined
    const trimmed = value.trim()
    if (!trimmed) return undefined
    return trimmed.length > MAX_FIELD_CHARS
        ? trimmed.slice(0, MAX_FIELD_CHARS)
        : trimmed
}

function asFiniteNumber(value: unknown): number | undefined {
    return typeof value === 'number' && Number.isFinite(value)
        ? value
        : undefined
}

function asRecord(value: unknown): Record<string, unknown> | null {
    return typeof value === 'object' && value !== null && !Array.isArray(value)
        ? (value as Record<string, unknown>)
        : null
}

function capList<T>(
    value: unknown,
    cap: number,
    map: (item: Record<string, unknown>) => T | null,
): T[] | undefined {
    if (!Array.isArray(value)) return undefined
    const out: T[] = []
    for (const raw of value) {
        if (out.length >= cap) break
        const record = asRecord(raw)
        if (!record) continue
        const mapped = map(record)
        if (mapped !== null) out.push(mapped)
    }
    return out.length > 0 ? out : undefined
}

/**
 * Defensive normalization of a client-supplied context payload: unknown
 * fields are dropped, strings are trimmed and bounded, lists truncated to
 * the caps. Both mint entry points (the Convex action and the HTTP route)
 * run their payload through this before rendering the prompt.
 */
export function sanitizeAgentContext(raw: unknown): AgentUserContext {
    const record = asRecord(raw)
    if (!record) return {}

    const settingsRecord = asRecord(record.settings)
    const settings: AgentContextSettings | undefined = settingsRecord
        ? {
              defaultCurrency: asBoundedString(settingsRecord.defaultCurrency),
              language: asBoundedString(settingsRecord.language),
              theme: asBoundedString(settingsRecord.theme),
          }
        : undefined

    return {
        userName: asBoundedString(record.userName),
        userEmail: asBoundedString(record.userEmail),
        settings,
        accounts: capList(record.accounts, AGENT_CONTEXT_CAPS.accounts, (a) => {
            const id = asBoundedString(a.id)
            const name = asBoundedString(a.name)
            const currency = asBoundedString(a.currency)
            if (!id || !name || !currency) return null
            const account: AgentContextAccount = { id, name, currency }
            if (a.isArchived === true) account.isArchived = true
            return account
        }),
        categories: capList(
            record.categories,
            AGENT_CONTEXT_CAPS.categories,
            (c) => {
                const id = asBoundedString(c.id)
                const name = asBoundedString(c.name)
                if (!id || !name) return null
                return { id, name }
            },
        ),
        tags: capList(record.tags, AGENT_CONTEXT_CAPS.tags, (t) => {
            const id = asBoundedString(t.id)
            const name = asBoundedString(t.name)
            if (!id || !name) return null
            const tag: AgentContextTag = { id, name }
            const parentId = asBoundedString(t.parentId)
            if (parentId) tag.parentId = parentId
            return tag
        }),
        recentTransactions: capList(
            record.recentTransactions,
            AGENT_CONTEXT_CAPS.recentTransactions,
            (t) => {
                const name = asBoundedString(t.name)
                const currency = asBoundedString(t.currency)
                const type = asBoundedString(t.type)
                const date = asBoundedString(t.date)
                const amount = asFiniteNumber(t.amount)
                if (!name || !currency || !type || !date) return null
                if (amount === undefined) return null
                const txn: AgentContextTransaction = {
                    name,
                    amount,
                    currency,
                    type,
                    date,
                }
                const account = asBoundedString(t.account)
                if (account) txn.account = account
                const category = asBoundedString(t.category)
                if (category) txn.category = category
                return txn
            },
        ),
        memories: capList(record.memories, AGENT_CONTEXT_CAPS.memories, (m) => {
            const id = asBoundedString(m.id)
            const content = asBoundedString(m.content)
            if (!id || !content) return null
            return { id, content }
        }),
    }
}
