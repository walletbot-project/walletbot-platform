import { api } from '@wallet-bot/backend/api'
import type { AgentUserContext } from '@wallet-bot/shared'
import { AGENT_CONTEXT_CAPS } from '@wallet-bot/shared'
import type { ConvexReactClient } from 'convex/react'
import { readLanguagePreference } from '@/lib/i18n'
import { readThemePreference } from '@/lib/theme/preference'

/**
 * The arguments `v1/live/actions:requestLiveToken` accepts — platform
 * identity, the user's locale/timezone (for the prompt's date line), and the
 * USER_CONTEXT snapshot rendered into the system prompt.
 */
export type LiveTokenMintArgs = {
    platform: string
    appVersion: string
    locale: string
    timezone?: string
    timezoneOffsetMinutes: number
    context: AgentUserContext
}

function pad(value: number): string {
    return String(value).padStart(2, '0')
}

/** Local wall-clock "YYYY-MM-DD HH:mm" for the snapshot's movement lines. */
function formatLocalDate(ms: number): string {
    const date = new Date(ms)
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`
}

/**
 * Builds the mint request from the web client's own source of truth (its
 * Convex queries), mirroring what native builds from Drift. Best-effort by
 * design: a failed read drops its section rather than blocking the session —
 * the server treats every field as optional.
 */
export async function buildLiveTokenMintArgs(opts: {
    client: ConvexReactClient
    user: { name: string; email: string } | null
    locale: string
}): Promise<LiveTokenMintArgs> {
    const { client, user, locale } = opts

    const context: AgentUserContext = {}
    if (user?.name) context.userName = user.name
    if (user?.email) context.userEmail = user.email

    const [settings, accounts, categories, tags, recent, memories] =
        await Promise.all([
            client
                .query(api.v1.users.queries.getSettings, {})
                .catch(() => null),
            client
                .query(api.v1.accounts.queries.list, {
                    includeArchived: false,
                })
                .catch(() => null),
            client
                .query(api.v1.categories.queries.listActive)
                .catch(() => null),
            client.query(api.v1.tags.queries.listActive).catch(() => null),
            client
                .query(api.v1.transactions.queries.recent, {
                    limit: AGENT_CONTEXT_CAPS.recentTransactions,
                })
                .catch(() => null),
            client.query(api.v1.memories.queries.listActive).catch(() => null),
        ])

    context.settings = {
        ...(settings ? { defaultCurrency: settings.defaultCurrency } : {}),
        language: readLanguagePreference(),
        theme: readThemePreference(),
    }
    if (accounts) {
        context.accounts = accounts
            .slice(0, AGENT_CONTEXT_CAPS.accounts)
            .map((a) => ({ id: a.id, name: a.name, currency: a.currency }))
    }
    if (categories) {
        context.categories = categories
            .slice(0, AGENT_CONTEXT_CAPS.categories)
            .map((c) => ({ id: c.id, name: c.name }))
    }
    if (tags) {
        context.tags = tags.slice(0, AGENT_CONTEXT_CAPS.tags).map((t) => ({
            id: t.id,
            name: t.name,
            ...(t.parentId ? { parentId: t.parentId } : {}),
        }))
    }
    if (recent) {
        const accountNames = new Map(
            (accounts ?? []).map((a) => [a.id, a.name]),
        )
        const categoryNames = new Map(
            (categories ?? []).map((c) => [c.id, c.name]),
        )
        context.recentTransactions = recent
            .slice(0, AGENT_CONTEXT_CAPS.recentTransactions)
            .map((t) => ({
                name: t.name,
                amount: Number(t.amount) / 100,
                currency: t.currency,
                type: t.type,
                ...(accountNames.has(t.accountId)
                    ? { account: accountNames.get(t.accountId) }
                    : {}),
                ...(categoryNames.has(t.categoryId)
                    ? { category: categoryNames.get(t.categoryId) }
                    : {}),
                date: formatLocalDate(Number(t.date)),
            }))
    }

    if (memories && memories.length > 0) {
        context.memories = memories.slice(0, AGENT_CONTEXT_CAPS.memories)
    }

    let timezone: string | undefined
    try {
        timezone = Intl.DateTimeFormat().resolvedOptions().timeZone
    } catch {
        timezone = undefined
    }

    return {
        platform: 'web',
        // The web client ships with the backend, so it carries no meaningful
        // version; the mint treats platform 'web' as unrestricted.
        appVersion: '0.0.0',
        locale,
        ...(timezone ? { timezone } : {}),
        timezoneOffsetMinutes: -new Date().getTimezoneOffset(),
        context,
    }
}
