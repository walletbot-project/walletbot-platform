import { Migrations } from '@convex-dev/migrations'
import { computeExchangeRate } from '@wallet-bot/shared'
import { paginationOptsValidator } from 'convex/server'
import { components } from './_generated/api'
import type { DataModel } from './_generated/dataModel'
import { internalQuery } from './_generated/server'
import { nextSeq } from './sync/helpers'

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

// Backfills exchangeRate on cross-currency transfers to the current rule (the
// larger amount over the smaller, always >= 1). Historical rows were written
// with the previous formula (toAmount / amount), which could be < 1.
//
// A plain field patch would NOT reach clients: sync pull gates on `seq > since`
// and `ctx.db.patch` does not touch `seq`. So each corrected row must also
// allocate a fresh `seq` and bump `updatedAt` — otherwise the backfill stays
// server-only (and clean client rows never re-pull it, dirty ones reject it).
// exchangeRate is not part of the inflow/outflow aggregates, so a raw patch that
// leaves amount/toAmount untouched needs no aggregate bookkeeping.
export const backfillTransferExchangeRate = migrations.define({
    table: 'transactions',
    migrateOne: async (ctx, transaction) => {
        if (transaction.type !== 'transfer') return
        const { currency, toCurrency, amount, toAmount } = transaction
        if (
            toCurrency === undefined ||
            toAmount === undefined ||
            toCurrency === currency
        ) {
            return
        }
        const exchangeRate = computeExchangeRate(
            Number(amount),
            Number(toAmount),
        )
        if (exchangeRate === undefined) return
        // Idempotent: recomputing the same inputs yields the same float, so
        // already-correct rows are skipped and re-runs cost no seq churn.
        if (transaction.exchangeRate === exchangeRate) return
        const seq = await nextSeq(ctx, transaction.userId)
        return { exchangeRate, seq, updatedAt: BigInt(Date.now()) }
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

// Read-only preview for the exchangeRate backfill. Same bigint dry-run caveat as
// above: bounded, never writes. Counts cross-currency transfers whose stored
// rate differs from the recomputed one.
export const previewTransferExchangeRateBackfill = internalQuery({
    args: { paginationOpts: paginationOptsValidator },
    handler: async (ctx, args) => {
        const page = await ctx.db
            .query('transactions')
            .paginate(args.paginationOpts)
        const stale = page.page.filter((transaction) => {
            if (transaction.type !== 'transfer') return false
            const { currency, toCurrency, amount, toAmount } = transaction
            if (
                toCurrency === undefined ||
                toAmount === undefined ||
                toCurrency === currency
            ) {
                return false
            }
            const exchangeRate = computeExchangeRate(
                Number(amount),
                Number(toAmount),
            )
            if (exchangeRate === undefined) return false
            return transaction.exchangeRate !== exchangeRate
        })
        return {
            continueCursor: page.continueCursor,
            isDone: page.isDone,
            scanned: page.page.length,
            wouldUpdate: stale.length,
            sampleIds: stale.slice(0, 10).map((transaction) => transaction.id),
        }
    },
})
