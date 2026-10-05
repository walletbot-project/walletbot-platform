import { adjustmentAmount, ledgerDelta } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internal } from '../_generated/api'
import type { Doc } from '../_generated/dataModel'
import type { QueryCtx } from '../_generated/server'
import { internalMutation, internalQuery } from '../_generated/server'
import {
    accountNamespace,
    inflowsByAccount,
    outflowsByAccount,
} from '../aggregates'
import { balanceBeforeInLedger, reconcileAdjustment } from './helpers'

// One-time backfill for WAL-188: balance adjustments became declarations
// whose amount is re-derived on every write before them, but rows written
// before that — by the web, the agent, or with a back-dated date — may still
// carry an amount computed against a different balance.
//
// The live reconciliation only fixes the first adjustment after a write and
// assumes every earlier one is already right, so it cannot repair stale data
// on its own. This walks every account's live adjustments in ledger order
// (oldest first), so each one is measured against already-corrected ones.
//
// Rollout, all from `npx convex run`:
//   1. transactions/adjustmentBackfill:verifyAggregates — page through until
//      done; any mismatch means the aggregates must be rebuilt first
//      (transactions/backfill), or the corrected amounts will be wrong.
//   2. transactions/adjustmentBackfill:preview — page through until done;
//      reports what would change and every adjustment without balanceAfter
//      whose amount is not 0 (the rule takes those to 0, moving the balance).
//   3. transactions/adjustmentBackfill:run — writes, re-scheduling itself one
//      page of adjustments at a time; every change is logged.
//   4. preview again — must report no changes.
//
// Idempotent: an adjustment already right is not written, so a re-run (or a
// chain interrupted half way) only does the remaining work.

const ACCOUNT_BATCH = 50
const ADJUSTMENT_BATCH = 50
const PREVIEW_SAMPLE = 50
// Per account, in verifyAggregates: rows read from each side (source and
// transfer destination) before the account is reported as not checked.
const VERIFY_ROW_CAP = 4000

function liveAdjustments(ctx: QueryCtx, userId: string, accountId: string) {
    return ctx.db
        .query('transactions')
        .withIndex('by_user_account_type_archived_date', (q) =>
            q
                .eq('userId', userId)
                .eq('accountId', accountId)
                .eq('type', 'balance_adjustment')
                .eq('isArchived', false),
        )
}

type PlannedChange = {
    userId: string
    accountId: string
    id: string
    date: number
    from: number
    to: number
    hasBalanceAfter: boolean
}

/**
 * What `run` would change, without writing. Simulates the ledger-order walk:
 * correcting an adjustment by d moves the balance before every later one on
 * the account by d, so later amounts are measured against the corrected
 * earlier ones, exactly as `run` will.
 */
export const preview = internalQuery({
    args: {
        cursor: v.union(v.string(), v.null()),
        numAccounts: v.optional(v.number()),
    },
    handler: async (ctx, args) => {
        const page = await ctx.db.query('accounts').paginate({
            numItems: args.numAccounts ?? ACCOUNT_BATCH,
            cursor: args.cursor,
        })

        let adjustments = 0
        let wouldChange = 0
        let missingBalanceAfterNonZero = 0
        const sample: PlannedChange[] = []
        const missingBalanceAfter: PlannedChange[] = []

        for (const account of page.page) {
            let shift = 0n
            for await (const adjustment of liveAdjustments(
                ctx,
                account.userId,
                account.id,
            )) {
                adjustments++
                const previous =
                    (await balanceBeforeInLedger(
                        ctx,
                        account.userId,
                        account.id,
                        adjustment,
                    )) + shift
                const amount = adjustmentAmount(
                    adjustment.balanceAfter ?? previous,
                    previous,
                )
                if (amount === adjustment.amount) continue
                shift += amount - adjustment.amount
                wouldChange++
                const change: PlannedChange = {
                    userId: account.userId,
                    accountId: account.id,
                    id: adjustment.id,
                    date: Number(adjustment.date),
                    from: Number(adjustment.amount),
                    to: Number(amount),
                    hasBalanceAfter: adjustment.balanceAfter !== undefined,
                }
                if (adjustment.balanceAfter === undefined) {
                    missingBalanceAfterNonZero++
                    missingBalanceAfter.push(change)
                }
                if (sample.length < PREVIEW_SAMPLE) sample.push(change)
            }
        }

        return {
            isDone: page.isDone,
            continueCursor: page.continueCursor,
            accounts: page.page.length,
            adjustments,
            wouldChange,
            missingBalanceAfterNonZero,
            missingBalanceAfter,
            sample,
        }
    },
})

/**
 * Compares each account's aggregate total with the sum of its live rows. The
 * backfill derives amounts from the aggregates, so they must agree first.
 */
export const verifyAggregates = internalQuery({
    args: {
        cursor: v.union(v.string(), v.null()),
        numAccounts: v.optional(v.number()),
    },
    handler: async (ctx, args) => {
        const page = await ctx.db
            .query('accounts')
            .paginate({ numItems: args.numAccounts ?? 10, cursor: args.cursor })

        const mismatches: {
            userId: string
            accountId: string
            aggregate: number
            rows: number
        }[] = []
        const notChecked: { userId: string; accountId: string }[] = []

        for (const account of page.page) {
            const [source, destination] = await Promise.all([
                ctx.db
                    .query('transactions')
                    .withIndex('by_user_account_date', (q) =>
                        q
                            .eq('userId', account.userId)
                            .eq('accountId', account.id),
                    )
                    .take(VERIFY_ROW_CAP + 1),
                ctx.db
                    .query('transactions')
                    .withIndex('by_user_to_account_date', (q) =>
                        q
                            .eq('userId', account.userId)
                            .eq('toAccountId', account.id),
                    )
                    .take(VERIFY_ROW_CAP + 1),
            ])
            if (
                source.length > VERIFY_ROW_CAP ||
                destination.length > VERIFY_ROW_CAP
            ) {
                notChecked.push({
                    userId: account.userId,
                    accountId: account.id,
                })
                continue
            }

            const rows = new Map<string, Doc<'transactions'>>()
            for (const row of [...source, ...destination]) rows.set(row.id, row)
            let rowSum = 0n
            for (const row of rows.values()) {
                rowSum += ledgerDelta(row, account.id)
            }

            const namespace = accountNamespace(account.userId, account.id)
            const [outflows, inflows] = await Promise.all([
                outflowsByAccount.sum(ctx, { namespace }),
                inflowsByAccount.sum(ctx, { namespace }),
            ])
            const aggregate = BigInt(Math.round(outflows + inflows))
            if (aggregate !== rowSum) {
                mismatches.push({
                    userId: account.userId,
                    accountId: account.id,
                    aggregate: Number(aggregate),
                    rows: Number(rowSum),
                })
            }
        }

        return {
            isDone: page.isDone,
            continueCursor: page.continueCursor,
            accounts: page.page.length,
            mismatches,
            notChecked,
        }
    },
})

const accountRef = v.object({ userId: v.string(), accountId: v.string() })

/**
 * Reconciles every live adjustment, account by account, oldest first. Each
 * invocation handles one page of one account's adjustments and re-schedules
 * itself; the chain is sequential, so a user's sync counter is never bumped
 * by two invocations at once. Start it with no arguments.
 */
export const run = internalMutation({
    args: {
        accountCursor: v.optional(v.union(v.string(), v.null())),
        accountsDone: v.optional(v.boolean()),
        pending: v.optional(v.array(accountRef)),
        adjustmentCursor: v.optional(v.union(v.string(), v.null())),
        scanned: v.optional(v.number()),
        changed: v.optional(v.number()),
    },
    handler: async (ctx, args) => {
        let accountCursor = args.accountCursor ?? null
        let accountsDone = args.accountsDone ?? false
        let pending = args.pending ?? []
        let adjustmentCursor = args.adjustmentCursor ?? null
        let scanned = args.scanned ?? 0
        let changed = args.changed ?? 0

        // Convex allows one `.paginate()` per function execution, so an
        // invocation either loads the next page of accounts or walks one page
        // of one account's adjustments — never both.
        const [current, ...rest] = pending
        if (!current) {
            if (accountsDone) {
                console.log(
                    `adjustmentBackfill: done — ${scanned} adjustments scanned, ${changed} changed`,
                )
                return { done: true, scanned, changed }
            }
            const page = await ctx.db
                .query('accounts')
                .paginate({ numItems: ACCOUNT_BATCH, cursor: accountCursor })
            pending = page.page.map((a) => ({
                userId: a.userId,
                accountId: a.id,
            }))
            accountCursor = page.continueCursor
            accountsDone = page.isDone
        } else {
            const page = await liveAdjustments(
                ctx,
                current.userId,
                current.accountId,
            ).paginate({
                numItems: ADJUSTMENT_BATCH,
                cursor: adjustmentCursor,
            })
            for (const adjustment of page.page) {
                scanned++
                const change = await reconcileAdjustment(ctx, adjustment)
                if (!change) continue
                changed++
                console.log(
                    `adjustmentBackfill: user=${current.userId} account=${current.accountId} adjustment=${adjustment.id} amount ${change.from} -> ${change.to}`,
                )
            }
            if (page.isDone) {
                pending = rest
                adjustmentCursor = null
            } else {
                adjustmentCursor = page.continueCursor
            }
        }

        await ctx.scheduler.runAfter(
            0,
            internal.transactions.adjustmentBackfill.run,
            {
                accountCursor,
                accountsDone,
                pending,
                adjustmentCursor,
                scanned,
                changed,
            },
        )
        return { done: false, scanned, changed }
    },
})
