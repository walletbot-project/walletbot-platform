import { USABILITY_FIELDS, usabilityFieldError } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internal } from '../../_generated/api'
import type { Id } from '../../_generated/dataModel'
import { type MutationCtx, mutation } from '../../_generated/server'
import { requireAdmin } from '../../featureFlags/helpers'
import { usabilityFieldValueValidator } from '../../schema/usability'
import { parseCivilDay } from '../../usability/datasets'
import { randomCode } from '../../usability/utils'
import { workflow } from '../../usability/workflow'
import { requireAuth } from '../../users/helpers'

const PASSWORD_LENGTH = 10
const EMAIL_TAG_LENGTH = 4
const MAX_RECORDING_NAME_LENGTH = 256

async function requireAdminUser(ctx: MutationCtx): Promise<string> {
    const userId = await requireAuth(ctx)
    await requireAdmin(ctx, userId)
    return userId
}

async function upsertField(
    ctx: MutationCtx,
    sessionId: Id<'usabilitySessions'>,
    key: string,
    value: string | number | boolean | string[] | null,
    userId: string,
): Promise<void> {
    const existing = await ctx.db
        .query('usabilityFields')
        .withIndex('by_sessionId_and_key', (q) =>
            q.eq('sessionId', sessionId).eq('key', key),
        )
        .unique()
    const now = Date.now()
    if (existing) {
        await ctx.db.patch(existing._id, {
            value,
            updatedAt: now,
            updatedBy: userId,
        })
    } else {
        await ctx.db.insert('usabilityFields', {
            sessionId,
            key,
            value,
            updatedAt: now,
            updatedBy: userId,
        })
    }
}

async function requireSession(
    ctx: MutationCtx,
    sessionId: Id<'usabilitySessions'>,
) {
    const session = await ctx.db.get(sessionId)
    if (!session) throw new Error('Usability session not found')
    return session
}

export const create = mutation({
    args: {
        group: v.union(v.literal(1), v.literal(2)),
        sessionDay: v.string(),
    },
    handler: async (ctx, args) => {
        const userId = await requireAdminUser(ctx)
        if (!parseCivilDay(args.sessionDay)) {
            throw new Error('Invalid session day')
        }
        const last = await ctx.db
            .query('usabilitySessions')
            .withIndex('by_number')
            .order('desc')
            .first()
        const sessionId = await ctx.db.insert('usabilitySessions', {
            number: (last?.number ?? 0) + 1,
            group: args.group,
            sessionDay: args.sessionDay,
            password: randomCode(PASSWORD_LENGTH),
            emailTag: randomCode(EMAIL_TAG_LENGTH),
            status: 'provisioning',
            users: [],
            scenario0Seeded: false,
            scenario2Cursor: 0,
            createdBy: userId,
            createdAt: Date.now(),
        })
        await workflow.start(
            ctx,
            internal.usability.workflow.provisionSession,
            {
                sessionId,
            },
        )
        return sessionId
    },
})

export const retryProvisioning = mutation({
    args: { sessionId: v.id('usabilitySessions') },
    handler: async (ctx, { sessionId }) => {
        await requireAdminUser(ctx)
        const session = await requireSession(ctx, sessionId)
        if (session.status !== 'failed') {
            throw new Error('Only a failed session can be retried')
        }
        await ctx.db.patch(sessionId, {
            status: 'provisioning',
            error: undefined,
        })
        await workflow.start(
            ctx,
            internal.usability.workflow.provisionSession,
            {
                sessionId,
            },
        )
    },
})

export const setField = mutation({
    args: {
        sessionId: v.id('usabilitySessions'),
        key: v.string(),
        value: usabilityFieldValueValidator,
    },
    handler: async (ctx, args) => {
        const userId = await requireAdminUser(ctx)
        await requireSession(ctx, args.sessionId)
        const error = usabilityFieldError(args.key, args.value)
        if (error) throw new Error(error)
        await upsertField(ctx, args.sessionId, args.key, args.value, userId)
    },
})

/** Stamps a timer with the server clock, so two phones never disagree. */
export const stampField = mutation({
    args: { sessionId: v.id('usabilitySessions'), key: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAdminUser(ctx)
        await requireSession(ctx, args.sessionId)
        if (USABILITY_FIELDS.get(args.key)?.kind !== 'timestamp') {
            throw new Error(`${args.key} is not a timer`)
        }
        const now = Date.now()
        await upsertField(ctx, args.sessionId, args.key, now, userId)
        return now
    },
})

export const generateRecordingUploadUrl = mutation({
    args: { sessionId: v.id('usabilitySessions') },
    handler: async (ctx, { sessionId }) => {
        await requireAdminUser(ctx)
        await requireSession(ctx, sessionId)
        return await ctx.storage.generateUploadUrl()
    },
})

/**
 * Attaches an uploaded recording to its session, replacing the previous one.
 * Size and type come from storage metadata, never from the client.
 */
export const attachRecording = mutation({
    args: {
        sessionId: v.id('usabilitySessions'),
        storageId: v.string(),
        name: v.string(),
    },
    handler: async (ctx, args) => {
        await requireAdminUser(ctx)
        const session = await requireSession(ctx, args.sessionId)
        const storageId = ctx.db.system.normalizeId('_storage', args.storageId)
        if (!storageId) throw new Error('Recording upload not found')
        const metadata = await ctx.db.system.get(storageId)
        if (!metadata) throw new Error('Recording upload not found')

        const contentType = metadata.contentType
        const isMedia =
            contentType?.startsWith('audio/') ||
            contentType?.startsWith('video/')
        if (!isMedia) {
            throw new Error('The recording must be an audio or video file')
        }

        const name = args.name.trim().slice(0, MAX_RECORDING_NAME_LENGTH)
        const previous = session.recording?.storageId
        await ctx.db.patch(args.sessionId, {
            recording: {
                storageId,
                name: name || 'grabacion',
                size: metadata.size,
                contentType,
                uploadedAt: Date.now(),
            },
        })
        if (previous && previous !== storageId) {
            await ctx.storage.delete(previous)
        }
    },
})
