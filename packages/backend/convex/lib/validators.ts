import { v } from 'convex/values'

/** ISO 4217 currency codes we support. */
export const SUPPORTED_CURRENCIES = ['USD', 'ARS', 'EUR', 'BRL'] as const
export type Currency = (typeof SUPPORTED_CURRENCIES)[number]

export const currencyValidator = v.union(
    v.literal('USD'),
    v.literal('ARS'),
    v.literal('EUR'),
    v.literal('BRL'),
)

/** YYYY-MM-DD date string. */
export const dateValidator = v.string()

/** Transaction types. */
export const TRANSACTION_TYPES = ['expense', 'income', 'transfer'] as const
export type TransactionType = (typeof TRANSACTION_TYPES)[number]

export const transactionTypeValidator = v.union(
    v.literal('expense'),
    v.literal('income'),
    v.literal('transfer'),
)

/** Account types. */
export const ACCOUNT_TYPES = ['asset', 'liability'] as const
export type AccountType = (typeof ACCOUNT_TYPES)[number]

export const accountTypeValidator = v.union(
    v.literal('asset'),
    v.literal('liability'),
)

/** Returns today as YYYY-MM-DD. */
export function todayDateString(): string {
    return new Date().toISOString().slice(0, 10)
}
