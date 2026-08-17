import { defineSchema } from 'convex/server'
import { accounts } from './schema/accounts'
import { agentUsageMonthly, agentUsageSamples } from './schema/agentUsage'
import { categories } from './schema/categories'
import { dashboardWidgets, savedFilters } from './schema/dashboard'
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
import { voiceSessionEvents, voiceSessions } from './schema/voice'

export default defineSchema({
    accounts,
    agentUsageMonthly,
    agentUsageSamples,
    categories,
    dashboardWidgets,
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
    voiceSessionEvents,
    voiceSessions,
})
