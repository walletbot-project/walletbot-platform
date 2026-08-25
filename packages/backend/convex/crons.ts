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
    internal.telemetry.mutations.deleteOldExportedMetrics,
    {
        olderThanMs: 24 * 60 * 60 * 1000,
        limit: 100,
    },
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
