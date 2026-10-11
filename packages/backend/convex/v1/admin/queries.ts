import { paginationOptsValidator } from 'convex/server'
import { v } from 'convex/values'
import { components } from '../../_generated/api'
import { query } from '../../_generated/server'
import { requireAdminCaller } from '../../admin/helpers'
import { transcriptLineFromEvent } from '../../admin/utils'
import { authComponent } from '../../auth'
import { isAdmin } from '../../featureFlags/helpers'

/**
 * Back-office reads. Every function here is admin-only and re-checks that on the
 * server; all of them are paginated over an index, because the tables they read
 * (feedback, users, voice history) grow without bound.
 */

/** Newest feedback first, with the submitter's email and attachment links. */
export const listFeedback = query({
    args: { paginationOpts: paginationOptsValidator },
    handler: async (ctx, args) => {
        await requireAdminCaller(ctx)
        const result = await ctx.db
            .query('feedback')
            .withIndex('by_createdAt')
            .order('desc')
            .paginate(args.paginationOpts)

        const page = await Promise.all(
            result.page.map(async (item) => {
                const submitter = item.userId
                    ? await authComponent.getAnyUserById(ctx, item.userId)
                    : null
                const attachments = await ctx.db
                    .query('feedbackAttachments')
                    .withIndex('by_feedbackId', (q) =>
                        q.eq('feedbackId', item._id),
                    )
                    .take(item.attachmentCount + 1)
                return {
                    id: item._id,
                    message: item.message,
                    email: submitter?.email ?? null,
                    reporter: item.userId ? 'account' : 'device',
                    platform: item.platform,
                    appVersion: item.appVersion ?? null,
                    locale: item.locale ?? null,
                    createdAt: item.createdAt,
                    attachments: await Promise.all(
                        attachments.map(async (attachment) => ({
                            id: attachment._id,
                            name: attachment.name,
                            size: attachment.size,
                            contentType: attachment.contentType ?? null,
                            url: await ctx.storage.getUrl(attachment.storageId),
                        })),
                    ),
                }
            }),
        )
        return { ...result, page }
    },
})

type AuthUserRow = {
    id: string
    email: string
    name: string
    emailVerified: boolean
    createdAt: number
}

/** The auth component hands back untyped documents; read only what we show. */
function toAuthUserRow(user: unknown): AuthUserRow | null {
    if (typeof user !== 'object' || user === null) return null
    if (!('_id' in user) || typeof user._id !== 'string') return null
    if (!('email' in user) || typeof user.email !== 'string') return null
    return {
        id: user._id,
        email: user.email,
        name: 'name' in user && typeof user.name === 'string' ? user.name : '',
        emailVerified: 'emailVerified' in user && user.emailVerified === true,
        createdAt:
            'createdAt' in user && typeof user.createdAt === 'number'
                ? user.createdAt
                : 0,
    }
}

/** Newest accounts first, over the auth component's creation-time order. */
export const listUsers = query({
    args: { paginationOpts: paginationOptsValidator },
    handler: async (ctx, args) => {
        await requireAdminCaller(ctx)
        const result = await ctx.runQuery(
            components.betterAuth.adapter.findMany,
            {
                model: 'user',
                paginationOpts: args.paginationOpts,
                sortBy: { field: 'createdAt', direction: 'desc' },
            },
        )

        const rows: AuthUserRow[] = []
        for (const user of result.page) {
            const row = toAuthUserRow(user)
            if (row) rows.push(row)
        }
        const page = await Promise.all(
            rows.map(async (row) => ({
                ...row,
                isAdmin: await isAdmin(ctx, row.id),
            })),
        )
        return {
            page,
            isDone: result.isDone,
            continueCursor: result.continueCursor,
        }
    },
})

/**
 * Exact-match lookup by email. There is deliberately no partial search: the auth
 * component has no search index on email, and filtering every user in memory is
 * not allowed.
 */
export const findUserByEmail = query({
    args: { email: v.string() },
    handler: async (ctx, args) => {
        await requireAdminCaller(ctx)
        const email = args.email.trim().toLowerCase()
        if (!email) return null
        const user = toAuthUserRow(
            await ctx.runQuery(components.betterAuth.adapter.findOne, {
                model: 'user',
                where: [{ field: 'email', value: email }],
            }),
        )
        if (!user) return null
        return { ...user, isAdmin: await isAdmin(ctx, user.id) }
    },
})

/** Newest voice sessions first, over the retention index. */
export const listTranscriptSessions = query({
    args: { paginationOpts: paginationOptsValidator },
    handler: async (ctx, args) => {
        await requireAdminCaller(ctx)
        const result = await ctx.db
            .query('voiceSessions')
            .withIndex('by_startedAt')
            .order('desc')
            .paginate(args.paginationOpts)

        const page = await Promise.all(
            result.page.map(async (session) => {
                const user = await authComponent.getAnyUserById(
                    ctx,
                    session.userId,
                )
                return {
                    id: session._id,
                    sessionId: session.sessionId,
                    userId: session.userId,
                    email: user?.email ?? null,
                    model: session.model,
                    status: session.status,
                    startedAt: session.startedAt,
                    endedAt: session.endedAt ?? null,
                }
            }),
        )
        return { ...result, page }
    },
})

/**
 * The conversation lines of one session, in order. Paginated over the session's
 * whole event log (native also stores audio chunks and protocol messages there),
 * so a page may hold few or no lines; the client keeps loading while more
 * remain.
 */
export const getTranscript = query({
    args: {
        userId: v.string(),
        sessionId: v.string(),
        paginationOpts: paginationOptsValidator,
    },
    handler: async (ctx, args) => {
        await requireAdminCaller(ctx)
        const result = await ctx.db
            .query('voiceSessionEvents')
            .withIndex('by_userId_and_sessionId_and_sequence', (q) =>
                q.eq('userId', args.userId).eq('sessionId', args.sessionId),
            )
            .paginate(args.paginationOpts)

        const page = result.page.flatMap((event) => {
            const line = transcriptLineFromEvent(event)
            return line
                ? [{ id: event._id, occurredAt: event.occurredAt, ...line }]
                : []
        })
        return { ...result, page }
    },
})
