import { ConvexError, v } from 'convex/values'
import { internal } from '../../_generated/api'
import { mutation } from '../../_generated/server'
import { CLIENT_OUTDATED, isClientSupported } from '../../config/helpers'
import {
    recordFunctionDuration,
    recordSyncError,
    type SyncErrorReason,
} from '../../telemetry/metrics'
import { requireAuth } from '../../users/helpers'
import { SYNC_VALIDATION_ERROR } from './internal'
import { pushTombstones, pushUpserts } from './validators'

const PUSH_FAILED = 'push_failed'

const isSyncValidationError = (error: unknown): boolean =>
    error instanceof ConvexError &&
    typeof error.data === 'object' &&
    error.data !== null &&
    'kind' in error.data &&
    error.data.kind === SYNC_VALIDATION_ERROR

// ─────────────────────────────────────────────────────────────────────────────
// Push handler.
//
// Each invocation is one chunk = one mutation = one bump of the user's
// counter. Failure modes, all returned as data except auth:
//  - `client_outdated` → client halts sync and shows the update prompt.
//  - `cursor_mismatch` → client must drain pull and retry (recoverable).
//  - `push_failed` → the batch threw (validation or bug). The batch runs in a
//    `ctx.runMutation` sub-transaction, so none of its writes commit; only
//    this mutation's telemetry does. Returned instead of rethrown because a
//    rethrow would roll the telemetry back too. Clients from before this
//    variant existed already treat an unknown `ok: false` as a failed round
//    and retry, exactly as they did for the throw.
//  - unauthenticated → `requireAuth` throws; not recorded (see
//    docs/metrics/error-rate-and-latency.md, "Coverage").
//
// Records one `system.function.duration_bucket_count` sample per call (the
// attempt count) and one `sync.errors.count` per non-ok outcome. Timed with
// `performance.now()`: `Date.now()` is frozen for a mutation's whole
// execution, `performance.now()` advances inside mutations.
// ─────────────────────────────────────────────────────────────────────────────

export const push = mutation({
    args: {
        expectedServerSeq: v.int64(),
        upserts: pushUpserts,
        tombstones: pushTombstones,
        platform: v.string(),
        appVersion: v.string(),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const startedAt = performance.now()
        const finish = async (
            status: 'ok' | 'rejected' | 'error',
            reason?: SyncErrorReason,
        ) => {
            if (reason !== undefined) {
                await recordSyncError(ctx, {
                    direction: 'push',
                    reason,
                    platform: args.platform,
                })
            }
            await recordFunctionDuration(ctx, {
                function: 'sync_push',
                durationMs: performance.now() - startedAt,
                status,
            })
        }

        // Reject clients below the platform floor before touching any data —
        // this is the write path that would otherwise diverge an incompatible
        // client's rows under LWW (docs/riesgos.md R-008). Fails open for a
        // client that can't report its version (unknown → supported).
        if (!isClientSupported(args.platform, args.appVersion)) {
            await finish('rejected', 'client_outdated')
            return { ok: false as const, error: CLIENT_OUTDATED }
        }

        // 1) CAS
        const counterRow = await ctx.db
            .query('syncCounters')
            .withIndex('by_user', (q) => q.eq('userId', userId))
            .unique()
        const currentCounter = counterRow?.value ?? 0n
        if (currentCounter !== args.expectedServerSeq) {
            await finish('rejected', 'cursor_mismatch')
            return {
                ok: false as const,
                error: 'cursor_mismatch' as const,
                currentCounter,
            }
        }

        // 2-4) Counter bump, upserts and tombstones, as one sub-transaction.
        let newSeq: bigint
        try {
            newSeq = await ctx.runMutation(
                internal.v1.sync.internal.applyPushBatch,
                {
                    userId,
                    currentCounter,
                    upserts: args.upserts,
                    tombstones: args.tombstones,
                },
            )
        } catch (error) {
            const reason: SyncErrorReason = isSyncValidationError(error)
                ? 'validation'
                : 'unknown'
            // Caught, so Convex no longer logs it as a failed call.
            console.error('sync push batch failed', {
                userId,
                reason,
                error: error instanceof Error ? error.message : String(error),
            })
            await finish('error', reason)
            return { ok: false as const, error: PUSH_FAILED, reason }
        }

        await finish('ok')
        return { ok: true as const, newSeq }
    },
})
