import { DEFAULT_CURRENCY, type Locale } from '@wallet-bot/shared'
import type { MutationCtx, QueryCtx } from '../../_generated/server'
import { type LanguageReport, resolveLanguageWrite } from './utils'

const readRow = (ctx: QueryCtx | MutationCtx, userId: string) =>
    ctx.db
        .query('userSettings')
        .withIndex('by_user', (q) => q.eq('userId', userId))
        .unique()

export async function getDefaultCurrency(
    ctx: QueryCtx | MutationCtx,
    userId: string,
): Promise<string> {
    const settings = await readRow(ctx, userId)
    return settings?.defaultCurrency ?? DEFAULT_CURRENCY
}

/**
 * The language the backend should address this user in, or `null` when no
 * client has ever reported one (a user who predates the setting, or one who
 * only ever ran a build that doesn't report it).
 *
 * `null` rather than a default on purpose: callers have better fallbacks than
 * a constant. Outbound email resolves it through `resolveOutboundLocale`
 * (emails/helpers.ts), which can still fall back to the request's
 * `Accept-Language` before giving up on `DEFAULT_LOCALE`.
 */
export async function getUserLanguage(
    ctx: QueryCtx | MutationCtx,
    userId: string,
): Promise<Locale | null> {
    const settings = await readRow(ctx, userId)
    return settings?.language ?? null
}

/** Everything `v1/users/queries:getSettings` returns, off a single read. */
export async function getSettingsForUser(
    ctx: QueryCtx | MutationCtx,
    userId: string,
): Promise<{ defaultCurrency: string; language: Locale | null }> {
    const settings = await readRow(ctx, userId)
    return {
        defaultCurrency: settings?.defaultCurrency ?? DEFAULT_CURRENCY,
        language: settings?.language ?? null,
    }
}

/**
 * Applies a language report, honouring the precedence rule in
 * `resolveLanguageWrite`. A no-op when the report loses or changes nothing,
 * which is the common case: clients re-report on every launch.
 *
 * `defaultCurrency` is written at its default when the row has to be created.
 * The column is required and `getDefaultCurrency` falls back to the same
 * constant, so this records no choice the user didn't make.
 */
export async function applyLanguageReport(
    ctx: MutationCtx,
    userId: string,
    incoming: LanguageReport,
): Promise<void> {
    const existing = await readRow(ctx, userId)

    const write = resolveLanguageWrite({ stored: existing, incoming })
    if (!write) return

    const now = BigInt(Date.now())
    if (existing) {
        await ctx.db.patch(existing._id, { ...write, updatedAt: now })
        return
    }
    await ctx.db.insert('userSettings', {
        userId,
        defaultCurrency: DEFAULT_CURRENCY,
        ...write,
        updatedAt: now,
    })
}
