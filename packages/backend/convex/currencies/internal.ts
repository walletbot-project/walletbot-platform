import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'
import { currencyValidator } from '../lib/validators'

export const storeExchangeRate = internalMutation({
    args: {
        fromCurrency: currencyValidator,
        toCurrency: currencyValidator,
        rate: v.number(),
        date: v.string(),
    },
    handler: async (ctx, args) => {
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
                source: 'api' as const,
            })
        } else {
            await ctx.db.insert('exchangeRates', {
                fromCurrency: args.fromCurrency,
                toCurrency: args.toCurrency,
                rate: args.rate,
                date: args.date,
                source: 'api',
            })
        }
    },
})
