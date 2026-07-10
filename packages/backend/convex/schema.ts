import { defineSchema } from 'convex/server'
import { accounts } from './schema/accounts'
import { categories } from './schema/categories'
import { dashboardWidgets, savedFilters } from './schema/dashboard'
import { refreshTokens } from './schema/refreshTokens'
import { syncCounters, tombstones } from './schema/sync'
import { tags } from './schema/tags'
import { transactions } from './schema/transactions'
import { transactionTags } from './schema/transactionTags'

export default defineSchema({
    accounts,
    categories,
    dashboardWidgets,
    refreshTokens,
    savedFilters,
    syncCounters,
    tags,
    tombstones,
    transactionTags,
    transactions,
})
