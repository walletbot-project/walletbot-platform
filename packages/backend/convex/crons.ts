import { cronJobs } from 'convex/server'
import { internal } from './_generated/api'
import { ORPHAN_ATTACHMENT_TTL_MS } from './feedback/utils'

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
        limit: 1000,
    },
)

crons.interval(
    'delete exported telemetry events',
    { hours: 6 },
    internal.telemetry.mutations.deleteOldExportedTelemetryEvents,
    {
        olderThanMs: 90 * 24 * 60 * 60 * 1000,
        limit: 1000,
    },
)

crons.interval(
    'delete failed telemetry metrics',
    { hours: 6 },
    internal.telemetry.mutations.deleteOldFailedTelemetryMetrics,
    {
        olderThanMs: 14 * 24 * 60 * 60 * 1000,
        limit: 1000,
    },
)

crons.interval(
    'delete failed telemetry events',
    { hours: 6 },
    internal.telemetry.mutations.deleteOldFailedTelemetryEvents,
    {
        olderThanMs: 14 * 24 * 60 * 60 * 1000,
        limit: 1000,
    },
)

crons.interval(
    'delete old agent usage samples',
    { hours: 6 },
    internal.telemetry.mutations.deleteOldAgentUsageSamples,
    {
        olderThanMs: 90 * 24 * 60 * 60 * 1000,
        limit: 1000,
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

// Market exchange rates for the agent's getExchangeRate tool. The Argentine
// markets move through the day; the central-bank reference rates behind the
// international set publish about once a day, so they are polled far less.
crons.interval(
    'refresh argentine exchange rates',
    { minutes: 30 },
    internal.exchangeRates.internal.refreshArgentineRates,
    {},
)

crons.interval(
    'refresh international exchange rates',
    { hours: 6 },
    internal.exchangeRates.internal.refreshInternationalRates,
    {},
)

// Feedback attachments go straight from the client to a Convex upload URL, so an
// abandoned or rejected submission leaves stored bytes with nothing pointing at
// them.
crons.interval(
    'delete orphaned feedback attachments',
    { hours: 6 },
    internal.feedback.internal.deleteOrphanAttachments,
    {
        olderThanMs: ORPHAN_ATTACHMENT_TTL_MS,
        limit: 100,
    },
)

// A purge batch that throws is never retried by the scheduler, which used to
// leave an account half-deleted forever. This is the only thing that finishes
// the job when that happens.
crons.interval(
    'revive stalled account deletions',
    { minutes: 10 },
    internal.userDeletion.internal.reviveStalledDeletions,
    {},
)

export default crons
