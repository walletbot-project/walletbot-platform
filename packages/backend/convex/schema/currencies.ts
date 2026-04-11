import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const currenciesTables = {
    exchangeRates: defineTable({
        fromCurrency: v.string(),
        toCurrency: v.string(),
        rate: v.number(), // e.g., 1 ARS = 0.00098 USD
        date: v.string(), // YYYY-MM-DD
        source: v.union(v.literal('manual'), v.literal('api')),
    }).index('by_fromCurrency_and_toCurrency_and_date', [
        'fromCurrency',
        'toCurrency',
        'date',
    ]),

    userSettings: defineTable({
        userId: v.string(),
        defaultCurrency: v.string(),
        locale: v.string(), // e.g., "en-US" — for future i18n
    }).index('by_userId', ['userId']),
}
