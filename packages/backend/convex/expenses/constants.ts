export const VALID_CATEGORIES = [
    'groceries',
    'transport',
    'dining',
    'entertainment',
    'utilities',
    'health',
    'shopping',
    'other',
] as const

export type ExpenseCategory = (typeof VALID_CATEGORIES)[number]

export const DEFAULT_CURRENCY = 'USD'
