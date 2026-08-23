import { defineSchema } from 'convex/server'
import { accounts } from './schema/accounts'
import { categories } from './schema/categories'
import { dashboardWidgets, savedFilters } from './schema/dashboard'
import {
    admins,
    featureFlagOverrides,
    featureFlags,
} from './schema/featureFlags'
import { feedback } from './schema/feedback'
import { refreshTokens } from './schema/refreshTokens'
import { supportEmails } from './schema/supportEmails'
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
import { deletedUsers, userDeletionRequests } from './schema/userDeletion'
import { userSettings } from './schema/userSettings'
import { voiceSessionEvents, voiceSessions } from './schema/voice'

export default defineSchema({
    accounts,
    admins,
    categories,
    dashboardWidgets,
    deletedUsers,
    featureFlagOverrides,
    featureFlags,
    feedback,
    refreshTokens,
    savedFilters,
    supportEmails,
    syncCounters,
    tags,
    telemetryEvents,
    telemetryMetrics,
    telemetryMetricSeries,
    termsAcceptances,
    tombstones,
    transactionTags,
    transactions,
    userDeletionRequests,
    userSettings,
    voiceSessionEvents,
    voiceSessions,
})
