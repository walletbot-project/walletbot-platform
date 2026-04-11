import { defineSchema } from 'convex/server'
import { accountsTables } from './schema/accounts'
import { categoriesTables } from './schema/categories'
import { currenciesTables } from './schema/currencies'
import { expensesTables } from './schema/expenses'
import { recurrencesTables } from './schema/recurrences'
import { tagsTables } from './schema/tags'
import { transactionsTables } from './schema/transactions'

export default defineSchema({
    // Legacy — will be removed after migration to transactions
    ...expensesTables,

    // Core
    ...accountsTables,
    ...categoriesTables,
    ...transactionsTables,
    ...tagsTables,

    // Multi-currency
    ...currenciesTables,

    // Recurring
    ...recurrencesTables,
})
