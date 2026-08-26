import {
    isValidCurrencyCode,
    MAX_LOCALE_TAG_LENGTH,
    resolveLocale,
} from '@wallet-bot/shared'
import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import { requireAuth } from '../../users/helpers'
import { applyLanguageReport } from './helpers'

export const updateDefaultCurrency = mutation({
    args: { currency: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        if (!isValidCurrencyCode(args.currency)) {
            throw new Error('Invalid currency code')
        }

        const existing = await ctx.db
            .query('userSettings')
            .withIndex('by_user', (q) => q.eq('userId', userId))
            .unique()

        const now = BigInt(Date.now())
        if (existing) {
            await ctx.db.patch(existing._id, {
                defaultCurrency: args.currency,
                updatedAt: now,
            })
        } else {
            await ctx.db.insert('userSettings', {
                userId,
                defaultCurrency: args.currency,
                updatedAt: now,
            })
        }
    },
})

/**
 * Records the language the backend addresses this user in: email today,
 * WhatsApp later. NOT the in-app display language, which stays device-scoped
 * on both clients.
 *
 * Called two ways. An explicit pick in Settings sends `source: 'explicit'`;
 * every authenticated app start sends whatever the device reports as
 * `source: 'device'`. `applyLanguageReport` decides which wins, so a repeat
 * report costs one indexed read and re-pushing is how a failed push heals.
 *
 * Clients send a raw BCP 47 tag (`es-AR`) and the server resolves it. That
 * keeps the mapping rule in one place instead of reimplementing it in Dart,
 * and it means a client can report a locale the product doesn't ship yet
 * without the call failing.
 */
export const updateLanguage = mutation({
    args: {
        tag: v.string(),
        source: v.union(v.literal('device'), v.literal('explicit')),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const tag = args.tag.trim()
        if (tag.length === 0 || tag.length > MAX_LOCALE_TAG_LENGTH) {
            throw new Error('Invalid locale tag')
        }
        await applyLanguageReport(ctx, userId, {
            language: resolveLocale(tag),
            source: args.source,
            tag,
        })
    },
})
