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
import { transactions } from './schema/transactions'
import { transactionTags } from './schema/transactionTags'
import { userSettings } from './schema/userSettings'
import { voiceSessionEvents, voiceSessions } from './schema/voice'
import {
    whatsappConversations,
    whatsappInboundMessages,
    whatsappOutboundMessages,
} from './schema/whatsapp'

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
    tombstones,
    transactionTags,
    transactions,
    userSettings,
    voiceSessionEvents,
    voiceSessions,
    whatsappConversations,
    whatsappInboundMessages,
    whatsappOutboundMessages,
})
