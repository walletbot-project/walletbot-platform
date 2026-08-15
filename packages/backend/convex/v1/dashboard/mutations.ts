import { v } from 'convex/values'
import type { MutationCtx } from '../../_generated/server'
import { mutation } from '../../_generated/server'
import { nextSeq, writeTombstone } from '../../sync/helpers'
import { requireAuth } from '../../users/helpers'

/** Guard on the per-user configuration tables — see queries.ts. */
const MAX_DASHBOARD_ROWS = 200

async function findWidget(ctx: MutationCtx, userId: string, id: string) {
    return await ctx.db
        .query('dashboardWidgets')
        .withIndex('by_user_id', (q) => q.eq('userId', userId).eq('id', id))
        .unique()
}

async function findFilter(ctx: MutationCtx, userId: string, id: string) {
    return await ctx.db
        .query('savedFilters')
        .withIndex('by_user_id', (q) => q.eq('userId', userId).eq('id', id))
        .unique()
}

export const createSavedFilter = mutation({
    args: { id: v.string(), name: v.string(), config: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const existing = await findFilter(ctx, userId, args.id)
        if (existing)
            throw new Error('Saved filter with that id already exists')

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())
        await ctx.db.insert('savedFilters', {
            userId,
            id: args.id,
            name: args.name,
            config: args.config,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq,
        })
        return args.id
    },
})

export const updateSavedFilter = mutation({
    args: {
        id: v.string(),
        name: v.optional(v.string()),
        config: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await findFilter(ctx, userId, args.id)
        if (!row) throw new Error('Saved filter not found')

        const seq = await nextSeq(ctx, userId)
        await ctx.db.patch(row._id, {
            ...(args.name !== undefined && { name: args.name }),
            ...(args.config !== undefined && { config: args.config }),
            updatedAt: BigInt(Date.now()),
            seq,
        })
    },
})

export const archiveSavedFilter = mutation({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await findFilter(ctx, userId, args.id)
        if (!row) return

        const seq = await nextSeq(ctx, userId)
        await ctx.db.patch(row._id, {
            isArchived: true,
            updatedAt: BigInt(Date.now()),
            seq,
        })
        await writeTombstone(ctx, {
            userId,
            tableName: 'savedFilters',
            entityId: args.id,
            seq,
        })
    },
})

export const createWidget = mutation({
    args: {
        id: v.string(),
        type: v.string(),
        filterId: v.optional(v.string()),
        position: v.number(),
        width: v.string(),
        options: v.string(),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const existing = await findWidget(ctx, userId, args.id)
        if (existing) throw new Error('Widget with that id already exists')

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())
        await ctx.db.insert('dashboardWidgets', {
            userId,
            id: args.id,
            type: args.type,
            filterId: args.filterId,
            position: args.position,
            width: args.width,
            options: args.options,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq,
        })
        return args.id
    },
})

export const updateWidget = mutation({
    args: {
        id: v.string(),
        type: v.optional(v.string()),
        // Explicit null clears the reference (a balance card has no filter).
        filterId: v.optional(v.union(v.string(), v.null())),
        position: v.optional(v.number()),
        width: v.optional(v.string()),
        options: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await findWidget(ctx, userId, args.id)
        if (!row) throw new Error('Widget not found')

        const seq = await nextSeq(ctx, userId)
        await ctx.db.patch(row._id, {
            ...(args.type !== undefined && { type: args.type }),
            ...(args.filterId !== undefined && {
                filterId: args.filterId ?? undefined,
            }),
            ...(args.position !== undefined && { position: args.position }),
            ...(args.width !== undefined && { width: args.width }),
            ...(args.options !== undefined && { options: args.options }),
            updatedAt: BigInt(Date.now()),
            seq,
        })
    },
})

export const archiveWidget = mutation({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await findWidget(ctx, userId, args.id)
        if (!row) return

        const seq = await nextSeq(ctx, userId)
        await ctx.db.patch(row._id, {
            isArchived: true,
            updatedAt: BigInt(Date.now()),
            seq,
        })
        await writeTombstone(ctx, {
            userId,
            tableName: 'dashboardWidgets',
            entityId: args.id,
            seq,
        })
    },
})

/**
 * Persists a whole layout in one transaction: each entry's grid coordinates
 * (already merged into its `options` JSON by the caller), width and row-major
 * `position`. One mutation so a drag never leaves the grid half-moved.
 */
export const saveLayout = mutation({
    args: {
        widgets: v.array(
            v.object({
                id: v.string(),
                position: v.number(),
                width: v.string(),
                options: v.string(),
            }),
        ),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        if (args.widgets.length > MAX_DASHBOARD_ROWS) {
            throw new Error('Too many widgets in one layout write')
        }
        const now = BigInt(Date.now())
        for (const entry of args.widgets) {
            const row = await findWidget(ctx, userId, entry.id)
            if (!row) continue
            const seq = await nextSeq(ctx, userId)
            await ctx.db.patch(row._id, {
                position: entry.position,
                width: entry.width,
                options: entry.options,
                updatedAt: now,
                seq,
            })
        }
    },
})

/**
 * Seeds the default dashboard for an account that has never had one.
 *
 * The ids are the same deterministic ones the native seed writes
 * (apps/native/lib/components/dashboard/default_dashboard.dart), so a device
 * and the web app seeding the same fresh account converge under last-writer-wins
 * instead of duplicating the layout. A tombstone on any dashboard row means the
 * user deliberately emptied their dashboard — never resurrect it.
 */
export const seedDefaultIfEmpty = mutation({
    args: {
        widgets: v.array(
            v.object({
                id: v.string(),
                type: v.string(),
                filterId: v.optional(v.string()),
                position: v.number(),
                width: v.string(),
                options: v.string(),
            }),
        ),
        filters: v.array(
            v.object({
                id: v.string(),
                name: v.string(),
                config: v.string(),
            }),
        ),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)

        const existing = await ctx.db
            .query('dashboardWidgets')
            .withIndex('by_user_seq', (q) => q.eq('userId', userId))
            .first()
        if (existing) return { seeded: false as const }

        const [widgetTombstone, filterTombstone] = await Promise.all([
            ctx.db
                .query('tombstones')
                .withIndex('by_user_table_entity', (q) =>
                    q.eq('userId', userId).eq('tableName', 'dashboardWidgets'),
                )
                .first(),
            ctx.db
                .query('tombstones')
                .withIndex('by_user_table_entity', (q) =>
                    q.eq('userId', userId).eq('tableName', 'savedFilters'),
                )
                .first(),
        ])
        if (widgetTombstone || filterTombstone) {
            return { seeded: false as const }
        }

        const now = BigInt(Date.now())
        for (const filter of args.filters) {
            if (await findFilter(ctx, userId, filter.id)) continue
            const seq = await nextSeq(ctx, userId)
            await ctx.db.insert('savedFilters', {
                userId,
                id: filter.id,
                name: filter.name,
                config: filter.config,
                isArchived: false,
                createdAt: now,
                updatedAt: now,
                seq,
            })
        }
        for (const widget of args.widgets) {
            if (await findWidget(ctx, userId, widget.id)) continue
            const seq = await nextSeq(ctx, userId)
            await ctx.db.insert('dashboardWidgets', {
                userId,
                id: widget.id,
                type: widget.type,
                filterId: widget.filterId,
                position: widget.position,
                width: widget.width,
                options: widget.options,
                isArchived: false,
                createdAt: now,
                updatedAt: now,
                seq,
            })
        }
        return { seeded: true as const }
    },
})
