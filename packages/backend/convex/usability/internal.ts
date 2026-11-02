import { v } from 'convex/values'
import type { Id } from '../_generated/dataModel'
import {
    internalMutation,
    internalQuery,
    type MutationCtx,
} from '../_generated/server'
import { usabilityScenarioValidator } from '../schema/usability'
import {
    type CivilDay,
    parseCivilDay,
    scenario0Plan,
    scenario2Plan,
} from './datasets'
import {
    insertPlanEntities,
    insertPlanTransaction,
    type PlanIds,
} from './utils'

/** Movements per mutation. Each one touches the sync counter and two aggregates. */
const BATCH_SIZE = 40

async function requireSession(
    ctx: MutationCtx,
    sessionId: Id<'usabilitySessions'>,
) {
    const session = await ctx.db.get(sessionId)
    if (!session) throw new Error('Usability session not found')
    return session
}

function sessionDayOf(value: string): CivilDay {
    const day = parseCivilDay(value)
    if (!day) throw new Error(`Invalid session day ${value}`)
    return day
}

function userFor(
    users: { scenario: 0 | 1 | 2; userId: string }[],
    scenario: 0 | 1 | 2,
): string {
    const user = users.find((item) => item.scenario === scenario)
    if (!user) throw new Error(`Scenario ${scenario} user was not created`)
    return user.userId
}

export const getSession = internalQuery({
    args: { sessionId: v.id('usabilitySessions') },
    handler: async (ctx, { sessionId }) => await ctx.db.get(sessionId),
})

export const recordUser = internalMutation({
    args: {
        sessionId: v.id('usabilitySessions'),
        scenario: usabilityScenarioValidator,
        userId: v.string(),
        email: v.string(),
    },
    handler: async (ctx, args) => {
        const session = await requireSession(ctx, args.sessionId)
        if (session.users.some((user) => user.scenario === args.scenario)) {
            return
        }
        await ctx.db.patch(args.sessionId, {
            users: [
                ...session.users,
                {
                    scenario: args.scenario,
                    userId: args.userId,
                    email: args.email,
                },
            ],
        })
    },
})

export const seedScenario0 = internalMutation({
    args: { sessionId: v.id('usabilitySessions') },
    handler: async (ctx, { sessionId }) => {
        const session = await requireSession(ctx, sessionId)
        if (session.scenario0Seeded) return
        const userId = userFor(session.users, 0)
        const plan = scenario0Plan(sessionDayOf(session.sessionDay))
        const ids = await insertPlanEntities(ctx, userId, plan)
        for (const txn of plan.transactions) {
            await insertPlanTransaction(ctx, userId, plan, ids, txn)
        }
        await ctx.db.patch(sessionId, { scenario0Seeded: true })
    },
})

export const seedScenario2Base = internalMutation({
    args: { sessionId: v.id('usabilitySessions') },
    handler: async (ctx, { sessionId }) => {
        const session = await requireSession(ctx, sessionId)
        if (session.scenario2Ids) return
        const userId = userFor(session.users, 2)
        const { plan, answers } = scenario2Plan(
            sessionDayOf(session.sessionDay),
        )
        const ids = await insertPlanEntities(ctx, userId, plan)
        await ctx.db.patch(sessionId, {
            scenario2Ids: ids,
            scenario2Cursor: 0,
            scenario2Answers: answers,
        })
    },
})

/**
 * Inserts the next slice of the scenario 2 movements. The plan is rebuilt from
 * the session day on every call (it is deterministic), and the cursor moves in
 * the same transaction as the inserts, so a retried batch never duplicates.
 */
export const seedScenario2Batch = internalMutation({
    args: { sessionId: v.id('usabilitySessions') },
    handler: async (ctx, { sessionId }): Promise<{ done: boolean }> => {
        const session = await requireSession(ctx, sessionId)
        const ids = session.scenario2Ids
        if (!ids) throw new Error('Scenario 2 entities were not created')
        const userId = userFor(session.users, 2)
        const { plan } = scenario2Plan(sessionDayOf(session.sessionDay))
        const from = session.scenario2Cursor
        const to = Math.min(from + BATCH_SIZE, plan.transactions.length)
        for (const txn of plan.transactions.slice(from, to)) {
            await insertPlanTransaction(ctx, userId, plan, ids, txn)
        }
        await ctx.db.patch(sessionId, { scenario2Cursor: to })
        return { done: to >= plan.transactions.length }
    },
})

export const seedDemoEntities = internalMutation({
    args: { userId: v.string(), sessionDay: v.string() },
    handler: async (ctx, { userId, sessionDay }): Promise<PlanIds> => {
        const { plan } = scenario2Plan(sessionDayOf(sessionDay))
        return await insertPlanEntities(ctx, userId, plan)
    },
})

export const seedDemoMovements = internalMutation({
    args: {
        userId: v.string(),
        sessionDay: v.string(),
        ids: v.record(v.string(), v.string()),
        cursor: v.number(),
    },
    handler: async (
        ctx,
        { userId, sessionDay, ids, cursor },
    ): Promise<{ cursor: number; done: boolean }> => {
        const { plan } = scenario2Plan(sessionDayOf(sessionDay))
        const to = Math.min(cursor + BATCH_SIZE, plan.transactions.length)
        for (const txn of plan.transactions.slice(cursor, to)) {
            await insertPlanTransaction(ctx, userId, plan, ids, txn)
        }
        return { cursor: to, done: to >= plan.transactions.length }
    },
})

export const finishProvisioning = internalMutation({
    args: { sessionId: v.id('usabilitySessions') },
    handler: async (ctx, { sessionId }) => {
        await requireSession(ctx, sessionId)
        await ctx.db.patch(sessionId, { status: 'ready', error: undefined })
    },
})

export const markFailed = internalMutation({
    args: { sessionId: v.id('usabilitySessions'), error: v.string() },
    handler: async (ctx, { sessionId, error }) => {
        await requireSession(ctx, sessionId)
        await ctx.db.patch(sessionId, {
            status: 'failed',
            error: error.slice(0, 1000),
        })
    },
})
