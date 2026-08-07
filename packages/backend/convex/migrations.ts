import { Migrations } from '@convex-dev/migrations'
import { paginationOptsValidator } from 'convex/server'
import { components } from './_generated/api'
import type { DataModel } from './_generated/dataModel'
import { internalQuery } from './_generated/server'

export const migrations = new Migrations<DataModel>(components.migrations)

// Deploy 1 (widen): timeStatus is optional so old rows remain valid while new
// writes always include it. Historical rows have no persisted evidence that
// their hour was explicit or approximate, so the conservative value is none.
export const backfillTransactionTimeStatus = migrations.define({
    table: 'transactions',
    migrateOne: (_ctx, transaction) => {
        if (transaction.timeStatus !== undefined) return
        return { timeStatus: 'none' as const }
    },
})

export const run = migrations.runner()

// Read-only fallback for validating the rollout. The migrations component's
// v0.3.5 dry-run uses JSON.stringify internally, which cannot serialize this
// table's int64 bigint fields. This preview is bounded and never writes data.
export const previewTransactionTimeStatusBackfill = internalQuery({
    args: { paginationOpts: paginationOptsValidator },
    handler: async (ctx, args) => {
        const page = await ctx.db
            .query('transactions')
            .paginate(args.paginationOpts)
        const missing = page.page.filter(
            (transaction) => transaction.timeStatus === undefined,
        )
        return {
            continueCursor: page.continueCursor,
            isDone: page.isDone,
            scanned: page.page.length,
            wouldUpdate: missing.length,
            sampleIds: missing
                .slice(0, 10)
                .map((transaction) => transaction.id),
        }
    },
})
