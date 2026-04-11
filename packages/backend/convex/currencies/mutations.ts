import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { requireAuth } from '../lib/auth'
import { currencyValidator } from '../lib/validators'

export const setExchangeRate = mutation({
    args: {
        fromCurrency: currencyValidator,
        toCurrency: currencyValidator,
        rate: v.number(),
        date: v.string(),
    },
    handler: async (ctx, args) => {
        await requireAuth(ctx)
        if (args.rate <= 0) throw new Error('Rate must be positive')
        if (args.fromCurrency === args.toCurrency)
            throw new Error('Currencies must be different')

        // Upsert: check if rate for this pair+date already exists
        const existing = await ctx.db
            .query('exchangeRates')
            .withIndex('by_fromCurrency_and_toCurrency_and_date', (q) =>
                q
                    .eq('fromCurrency', args.fromCurrency)
                    .eq('toCurrency', args.toCurrency)
                    .eq('date', args.date),
            )
            .first()

        if (existing) {
            await ctx.db.patch(existing._id, {
                rate: args.rate,
                source: 'manual' as const,
            })
        } else {
            await ctx.db.insert('exchangeRates', {
                fromCurrency: args.fromCurrency,
                toCurrency: args.toCurrency,
                rate: args.rate,
                date: args.date,
                source: 'manual',
            })
        }
    },
})
