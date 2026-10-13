import { defineSchema } from 'convex/server'
import { accounts } from './schema/accounts'
import { agentMemories } from './schema/agentMemories'
import { agentReports } from './schema/agentReports'
import { agentUsageMonthly, agentUsageSamples } from './schema/agentUsage'
import { appUsers } from './schema/appUsers'
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
import { occurrenceClock } from './schema/occurrenceClock'
import { recurrences } from './schema/recurrences'
import { refreshTokens } from './schema/refreshTokens'
import { supportEmails } from './schema/supportEmails'
import { syncConflicts, syncCounters, tombstones } from './schema/sync'
import { tags } from './schema/tags'
import {
    latencySamples,
    telemetryEvents,
    telemetryMetricSeries,
    telemetryMetrics,
} from './schema/telemetry'
import { transactions } from './schema/transactions'
import { transactionTags } from './schema/transactionTags'
import { usabilityFields, usabilitySessions } from './schema/usability'
import { deletedUsers, userDeletionRequests } from './schema/userDeletion'
import { userSettings } from './schema/userSettings'
import { voiceSessionEvents, voiceSessions } from './schema/voice'
import {
    whatsappConversations,
    whatsappInboundMessages,
    whatsappLinkCodes,
    whatsappOutboundMessages,
    whatsappWebhookRoutes,
} from './schema/whatsapp'

export default defineSchema({
    appUsers,
    occurrenceClock,
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
    recurrences,
    refreshTokens,
    savedFilters,
    supportEmails,
    syncConflicts,
    syncCounters,
    tags,
    telemetryEvents,
    telemetryMetrics,
    telemetryMetricSeries,
    latencySamples,
    tombstones,
    transactionTags,
    transactions,
    usabilityFields,
    usabilitySessions,
    userDeletionRequests,
    userSettings,
    voiceSessionEvents,
    voiceSessions,
    whatsappConversations,
    whatsappInboundMessages,
    whatsappLinkCodes,
    whatsappOutboundMessages,
    whatsappWebhookRoutes,
})
