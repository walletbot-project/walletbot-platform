import { v } from 'convex/values'
import { query } from '../_generated/server'
import { SUPPORTED_CURRENCIES } from '../lib/validators'

export const getExchangeRate = query({
    args: {
        fromCurrency: v.string(),
        toCurrency: v.string(),
        date: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        if (args.fromCurrency === args.toCurrency)
            return { rate: 1, date: args.date ?? '' }

        const date = args.date ?? '2099-12-31'

        // Get the closest rate on or before the given date
        const rate = await ctx.db
            .query('exchangeRates')
            .withIndex('by_fromCurrency_and_toCurrency_and_date', (q) =>
                q
                    .eq('fromCurrency', args.fromCurrency)
                    .eq('toCurrency', args.toCurrency)
                    .lte('date', date),
            )
            .order('desc')
            .first()

        if (!rate) return null

        return { rate: rate.rate, date: rate.date }
    },
})

export const listSupportedCurrencies = query({
    args: {},
    handler: async () => {
        return SUPPORTED_CURRENCIES.map((code) => ({
            code,
            // Symbol mapping — i18n keys used for full names
            symbol: CURRENCY_SYMBOLS[code],
        }))
    },
})

const CURRENCY_SYMBOLS: Record<string, string> = {
    USD: '$',
    ARS: 'AR$',
    EUR: '\u20AC',
    BRL: 'R$',
}
