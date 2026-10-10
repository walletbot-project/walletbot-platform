import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const usabilityScenarioValidator = v.union(
    v.literal(0),
    v.literal(1),
    v.literal(2),
)

export const usabilityFieldValueValidator = v.union(
    v.string(),
    v.number(),
    v.boolean(),
    v.array(v.string()),
    v.null(),
)

export const scenario2AnswersValidator = v.object({
    mercadoPagoBalanceCents: v.number(),
    hardware: v.object({
        amountCents: v.number(),
        accountName: v.string(),
        day: v.string(),
    }),
    supermarket: v.object({ totalCents: v.number(), count: v.number() }),
    months: v.object({
        previousMonth: v.string(),
        lastMonth: v.string(),
        previousTotalCents: v.number(),
        lastTotalCents: v.number(),
        categories: v.array(
            v.object({
                name: v.string(),
                previousCents: v.number(),
                lastCents: v.number(),
            }),
        ),
    }),
    martina: v.object({
        totalCents: v.number(),
        count: v.number(),
        withGiftCents: v.number(),
        withOldOutingCents: v.number(),
    }),
    fridge: v.object({ paidCount: v.number(), fourthDueDay: v.string() }),
    savings: v.object({
        currentUsdCents: v.number(),
        goalUsdCents: v.number(),
        monthlyUsdCents: v.number(),
        months: v.number(),
    }),
})

// One row per participant. The three test users and their data are generated
// by the provisioning workflow (usability/workflow.ts), which records its
// progress here so every step can be retried without duplicating anything.
export const usabilitySessions = defineTable({
    number: v.number(),
    group: v.union(v.literal(1), v.literal(2)),
    // The session day `S` in Argentina, `YYYY-MM-DD`. Every relative date in
    // the scenario datasets hangs off it.
    sessionDay: v.string(),
    // Shared by the three test users and visible to admins on purpose: the
    // accounts hold invented data and get logged in on the team's phone.
    password: v.string(),
    // Part of every test user's address, so a session never picks up an
    // account left behind by another one with the same number.
    emailTag: v.string(),
    status: v.union(
        v.literal('provisioning'),
        v.literal('ready'),
        v.literal('failed'),
    ),
    error: v.optional(v.string()),
    users: v.array(
        v.object({
            scenario: usabilityScenarioValidator,
            userId: v.string(),
            email: v.string(),
        }),
    ),
    scenario0Seeded: v.boolean(),
    scenario2Ids: v.optional(v.record(v.string(), v.string())),
    scenario2Cursor: v.number(),
    scenario2Answers: v.optional(scenario2AnswersValidator),
    recording: v.optional(
        v.object({
            storageId: v.id('_storage'),
            name: v.string(),
            size: v.number(),
            contentType: v.optional(v.string()),
            uploadedAt: v.number(),
        }),
    ),
    createdBy: v.string(),
    createdAt: v.number(),
})
    .index('by_number', ['number'])
    .index('by_recording_storageId', ['recording.storageId'])

export const usabilityFields = defineTable({
    sessionId: v.id('usabilitySessions'),
    key: v.string(),
    value: usabilityFieldValueValidator,
    updatedAt: v.number(),
    updatedBy: v.string(),
}).index('by_sessionId_and_key', ['sessionId', 'key'])
