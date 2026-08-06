import { defineSchema } from 'convex/server'
import { accounts } from './schema/accounts'
import { categories } from './schema/categories'
import { dashboardWidgets, savedFilters } from './schema/dashboard'
import { refreshTokens } from './schema/refreshTokens'
import { syncCounters, tombstones } from './schema/sync'
import { tags } from './schema/tags'
import { transactions } from './schema/transactions'
import { transactionTags } from './schema/transactionTags'
import { deletedUsers, userDeletionRequests } from './schema/userDeletion'
import { voiceSessionEvents, voiceSessions } from './schema/voice'

export default defineSchema({
    accounts,
    categories,
    dashboardWidgets,
    deletedUsers,
    refreshTokens,
    savedFilters,
    syncCounters,
    tags,
    tombstones,
    transactionTags,
    transactions,
    userDeletionRequests,
    voiceSessionEvents,
    voiceSessions,
})
