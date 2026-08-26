import { defineSchema } from 'convex/server'
import { accounts } from './schema/accounts'
import { agentMemories } from './schema/agentMemories'
import { agentReports } from './schema/agentReports'
import { agentUsageMonthly, agentUsageSamples } from './schema/agentUsage'
import { categories } from './schema/categories'
import { dashboardWidgets, savedFilters } from './schema/dashboard'
import { exchangeRates } from './schema/exchangeRates'
import {
    admins,
    featureFlagOverrides,
    featureFlags,
} from './schema/featureFlags'
import {
    feedback,
    feedbackAttachments,
    feedbackSweepState,
} from './schema/feedback'
import { legalAcceptances } from './schema/legal'
import { refreshTokens } from './schema/refreshTokens'
import { supportEmails } from './schema/supportEmails'
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
    agentUsageMonthly,
    agentUsageSamples,
    admins,
    agentMemories,
    agentReports,
    categories,
    dashboardWidgets,
    deletedUsers,
    exchangeRates,
    featureFlagOverrides,
    featureFlags,
    feedback,
    feedbackAttachments,
    feedbackSweepState,
    legalAcceptances,
    refreshTokens,
    savedFilters,
    supportEmails,
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
