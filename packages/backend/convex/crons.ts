import { cronJobs } from 'convex/server'
import { internal } from './_generated/api'

const crons = cronJobs()

crons.interval(
    'cleanup resend emails',
    { hours: 24 },
    internal.emails.internal.cleanupResendEmails,
    {},
)

crons.interval(
    'export pending telemetry events',
    { minutes: 5 },
    internal.telemetry.actions.exportPending,
    {},
)

crons.interval(
    'export pending telemetry metrics',
    { minutes: 5 },
    internal.telemetry.actions.exportPendingMetrics,
    {},
)

crons.interval(
    'retry failed telemetry event exports',
    { minutes: 15 },
    internal.telemetry.mutations.resetRetryableFailedEvents,
    {
        olderThanMs: 5 * 60 * 1000,
        maxAttempts: 6,
        limit: 100,
    },
)

crons.interval(
    'retry failed telemetry metrics exports',
    { minutes: 15 },
    internal.telemetry.mutations.resetRetryableFailedMetrics,
    {
        olderThanMs: 5 * 60 * 1000,
        maxAttempts: 6,
        limit: 100,
    },
)

crons.interval(
    'delete exported telemetry metrics',
    { hours: 6 },
    internal.telemetry.mutations.deleteOldExportedTelemetryMetrics,
    {
        olderThanMs: 90 * 24 * 60 * 60 * 1000,
        limit: 100,
    },
)

crons.interval(
    'delete exported telemetry events',
    { hours: 6 },
    internal.telemetry.mutations.deleteOldExportedTelemetryEvents,
    {
        olderThanMs: 90 * 24 * 60 * 60 * 1000,
        limit: 100,
    },
)

crons.interval(
    'delete failed telemetry metrics',
    { hours: 6 },
    internal.telemetry.mutations.deleteOldFailedTelemetryMetrics,
    {
        olderThanMs: 14 * 24 * 60 * 60 * 1000,
        limit: 100,
    },
)

crons.interval(
    'delete failed telemetry events',
    { hours: 6 },
    internal.telemetry.mutations.deleteOldFailedTelemetryEvents,
    {
        olderThanMs: 14 * 24 * 60 * 60 * 1000,
        limit: 100,
    },
)

crons.interval(
    'delete old agent usage samples',
    { hours: 6 },
    internal.telemetry.mutations.deleteOldAgentUsageSamples,
    {
        olderThanMs: 90 * 24 * 60 * 60 * 1000,
        limit: 100,
    },
)

crons.interval(
    'record registered users total',
    { hours: 6 },
    internal.telemetry.actions.recordRegisteredUsersTotal,
    {},
)

crons.interval(
    'record agent monthly usage',
    { hours: 6 },
    internal.telemetry.actions.recordAgentMonthlyUsage,
    {},
)

export default crons
