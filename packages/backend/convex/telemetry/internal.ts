import { internal } from '../_generated/api'
import { internalMutation } from '../_generated/server'

// The nightly telemetry pass: everything the eleven telemetry and metrics crons
// used to do on their own clocks, in one window.
//
// Convex counts function calls, and a cron tick that finds nothing to do counts
// like any other. The five-minute export cron alone was 288 ticks a day (576
// calls, since each one reserves rows through a mutation) on every deployment,
// dev ones included — for a queue the inserts already drain themselves through
// `scheduler.runAfter(0)`.
//
// This is a fan-out, not a chain: the mutation only schedules the steps, each at
// its own offset, in a single transaction. A step that throws takes nothing else
// down with it (the scheduler does not retry a failed run, so a chain would lose
// everything behind the failure), and Convex keeps one Schedules row per step.
// The offsets are what makes the pass take minutes instead of firing eleven jobs
// at the same instant.
//
// Order matters twice:
//   - the gauges go first, so the snapshots they insert leave with this run;
//   - the retry sweeps run before the export drain, so a row that failed
//     yesterday goes out tonight instead of waiting another day.
// The deletes go last: they only touch rows that aged out weeks ago, so nothing
// waits on them.

const SECOND = 1000
const MINUTE = 60 * SECOND
const DAY = 24 * 60 * MINUTE

/** Exported rows are kept for the same 90 days the retention docs promise. */
const EXPORTED_RETENTION_MS = 90 * DAY
/** A row that has not exported in two weeks never will. */
const FAILED_RETENTION_MS = 14 * DAY
/** Backend agent usage samples follow the exported-telemetry retention. */
const AGENT_USAGE_SAMPLE_RETENTION_MS = 90 * DAY

/**
 * How long a row has to sit in `failed` before the sweep retries it. Kept from
 * the old fifteen-minute retry cron: it only exists so a row that failed
 * seconds ago is not retried inside the same pass that failed it.
 */
const RETRY_FAILED_OLDER_THAN_MS = 5 * MINUTE
const MAX_EXPORT_ATTEMPTS = 6
const RETRY_BATCH = 100

/**
 * Rows per delete batch. `deleteOld*` clamps this internally (1000 for
 * metrics, 100 for the rest) and reschedules itself while a batch comes back
 * full, so this is a batch size, not a daily ceiling.
 */
const DELETE_BATCH = 1000

export const runDailyMaintenance = internalMutation({
    args: {},
    handler: async (ctx) => {
        await ctx.scheduler.runAfter(
            0,
            internal.telemetry.actions.recordRegisteredUsersTotal,
            {},
        )
        await ctx.scheduler.runAfter(
            30 * SECOND,
            internal.telemetry.actions.recordAgentMonthlyUsage,
            {},
        )

        await ctx.scheduler.runAfter(
            MINUTE,
            internal.telemetry.mutations.resetRetryableFailedEvents,
            {
                olderThanMs: RETRY_FAILED_OLDER_THAN_MS,
                maxAttempts: MAX_EXPORT_ATTEMPTS,
                limit: RETRY_BATCH,
            },
        )
        await ctx.scheduler.runAfter(
            75 * SECOND,
            internal.telemetry.mutations.resetRetryableFailedMetrics,
            {
                olderThanMs: RETRY_FAILED_OLDER_THAN_MS,
                maxAttempts: MAX_EXPORT_ATTEMPTS,
                limit: RETRY_BATCH,
            },
        )

        // Both drain themselves batch by batch while rows keep coming back.
        await ctx.scheduler.runAfter(
            90 * SECOND,
            internal.telemetry.actions.exportPending,
            {},
        )
        await ctx.scheduler.runAfter(
            2 * MINUTE,
            internal.telemetry.actions.exportPendingMetrics,
            {},
        )

        await ctx.scheduler.runAfter(
            3 * MINUTE,
            internal.telemetry.mutations.deleteOldExportedTelemetryEvents,
            { olderThanMs: EXPORTED_RETENTION_MS, limit: DELETE_BATCH },
        )
        await ctx.scheduler.runAfter(
            210 * SECOND,
            internal.telemetry.mutations.deleteOldExportedTelemetryMetrics,
            { olderThanMs: EXPORTED_RETENTION_MS, limit: DELETE_BATCH },
        )
        await ctx.scheduler.runAfter(
            4 * MINUTE,
            internal.telemetry.mutations.deleteOldFailedTelemetryEvents,
            { olderThanMs: FAILED_RETENTION_MS, limit: DELETE_BATCH },
        )
        await ctx.scheduler.runAfter(
            270 * SECOND,
            internal.telemetry.mutations.deleteOldFailedTelemetryMetrics,
            { olderThanMs: FAILED_RETENTION_MS, limit: DELETE_BATCH },
        )
        await ctx.scheduler.runAfter(
            5 * MINUTE,
            internal.telemetry.mutations.deleteOldAgentUsageSamples,
            {
                olderThanMs: AGENT_USAGE_SAMPLE_RETENTION_MS,
                limit: DELETE_BATCH,
            },
        )

        return null
    },
})
