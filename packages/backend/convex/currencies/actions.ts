import { internal } from '../_generated/api'
import { action } from '../_generated/server'
import { currencyValidator } from '../lib/validators'

/**
 * Fetch the current exchange rate between two currencies from a public API.
 * Stores the result in the exchangeRates table and returns it.
 */
export const fetchExchangeRate = action({
    args: {
        fromCurrency: currencyValidator,
        toCurrency: currencyValidator,
    },
    handler: async (ctx, args): Promise<{ rate: number; date: string }> => {
        const identity = await ctx.auth.getUserIdentity()
        if (!identity) throw new Error('Not authenticated')

        if (args.fromCurrency === args.toCurrency) {
            return { rate: 1, date: new Date().toISOString().slice(0, 10) }
        }

        // Use the free frankfurter.app API (no key needed, ECB data)
        const url = `https://api.frankfurter.app/latest?from=${args.fromCurrency}&to=${args.toCurrency}`
        const response = await fetch(url)
        if (!response.ok) {
            throw new Error(`Exchange rate API error: ${response.status}`)
        }

        const data = (await response.json()) as {
            date: string
            rates: Record<string, number>
        }
        const rate = data.rates[args.toCurrency]
        if (rate === undefined) {
            throw new Error(
                `Rate not found for ${args.fromCurrency} -> ${args.toCurrency}`,
            )
        }

        // Store the rate for future reference
        await ctx.runMutation(internal.currencies.internal.storeExchangeRate, {
            fromCurrency: args.fromCurrency,
            toCurrency: args.toCurrency,
            rate,
            date: data.date,
        })

        return { rate, date: data.date }
    },
})
