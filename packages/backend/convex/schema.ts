import { defineSchema } from 'convex/server'
import { accounts } from './schema/accounts'
import { categories } from './schema/categories'
import { dashboardWidgets, savedFilters } from './schema/dashboard'
import {
    admins,
    featureFlagOverrides,
    featureFlags,
} from './schema/featureFlags'
import { refreshTokens } from './schema/refreshTokens'
import { syncCounters, tombstones } from './schema/sync'
import { tags } from './schema/tags'
import {
    telemetryEvents,
    telemetryMetricSeries,
    telemetryMetrics,
} from './schema/telemetry'
import { termsAcceptances } from './schema/termsAcceptances'
import { transactions } from './schema/transactions'
import { transactionTags } from './schema/transactionTags'
import { userSettings } from './schema/userSettings'
import { voiceSessionEvents, voiceSessions } from './schema/voice'

export default defineSchema({
    accounts,
    admins,
    categories,
    dashboardWidgets,
    featureFlagOverrides,
    featureFlags,
    refreshTokens,
    savedFilters,
    syncCounters,
    tags,
    telemetryEvents,
    telemetryMetrics,
    telemetryMetricSeries,
    termsAcceptances,
    tombstones,
    transactionTags,
    transactions,
    userSettings,
    voiceSessionEvents,
    voiceSessions,
})
