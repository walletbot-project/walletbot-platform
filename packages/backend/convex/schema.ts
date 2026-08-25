import { defineSchema } from 'convex/server'
import { accounts } from './schema/accounts'
import { agentMemories } from './schema/agentMemories'
import { categories } from './schema/categories'
import { dashboardWidgets, savedFilters } from './schema/dashboard'
import { exchangeRates } from './schema/exchangeRates'
import {
    admins,
    featureFlagOverrides,
    featureFlags,
} from './schema/featureFlags'
import { legalAcceptances } from './schema/legal'
import { refreshTokens } from './schema/refreshTokens'
import { syncCounters, tombstones } from './schema/sync'
import { tags } from './schema/tags'
import {
    telemetryEvents,
    telemetryMetricSeries,
    telemetryMetrics,
} from './schema/telemetry'
import { transactions } from './schema/transactions'
import { transactionTags } from './schema/transactionTags'
import { deletedUsers, userDeletionRequests } from './schema/userDeletion'
import { userSettings } from './schema/userSettings'
import { voiceSessionEvents, voiceSessions } from './schema/voice'

export default defineSchema({
    accounts,
    admins,
    agentMemories,
    categories,
    dashboardWidgets,
    deletedUsers,
    exchangeRates,
    featureFlagOverrides,
    featureFlags,
    legalAcceptances,
    refreshTokens,
    savedFilters,
    syncCounters,
    tags,
    telemetryEvents,
    telemetryMetrics,
    telemetryMetricSeries,
    tombstones,
    transactionTags,
    transactions,
    userDeletionRequests,
    userSettings,
    voiceSessionEvents,
    voiceSessions,
})
