import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { requireAuth } from '../lib/auth'
import { getOtherCategoryId, SYSTEM_CATEGORIES } from './helpers'

export const createCategory = mutation({
    args: {
        name: v.string(),
        icon: v.string(),
        color: v.string(),
        parentId: v.optional(v.id('categories')),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)

        // Validate parent exists and is top-level (max 1 level nesting)
        if (args.parentId) {
            const parent = await ctx.db.get(args.parentId)
            if (!parent) throw new Error('Parent category not found')
            if (parent.parentId)
                throw new Error('Subcategories cannot have subcategories')
        }

        // Next sort order
        const existing = await ctx.db
            .query('categories')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .take(100)
        const maxSort = existing.reduce(
            (max, c) => Math.max(max, c.sortOrder),
            -1,
        )

        return await ctx.db.insert('categories', {
            userId: user._id,
            name: args.name.trim(),
            icon: args.icon,
            color: args.color,
            parentId: args.parentId,
            isSystem: false,
            sortOrder: maxSort + 1,
        })
    },
})

export const updateCategory = mutation({
    args: {
        categoryId: v.id('categories'),
        name: v.optional(v.string()),
        icon: v.optional(v.string()),
        color: v.optional(v.string()),
        parentId: v.optional(v.id('categories')),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        const category = await ctx.db.get(args.categoryId)
        if (!category) throw new Error('Category not found')
        if (category.isSystem && args.name) {
            throw new Error('Cannot rename system categories')
        }
        if (!category.isSystem && category.userId !== user._id) {
            throw new Error('Not authorized')
        }

        // Validate parent if changing
        if (args.parentId) {
            const parent = await ctx.db.get(args.parentId)
            if (!parent) throw new Error('Parent category not found')
            if (parent.parentId)
                throw new Error('Subcategories cannot have subcategories')
            if (args.parentId === args.categoryId)
                throw new Error('Category cannot be its own parent')
        }

        const { categoryId, ...updates } = args
        const patch: Record<string, string | typeof args.parentId> = {}
        if (updates.name !== undefined) patch.name = updates.name.trim()
        if (updates.icon !== undefined) patch.icon = updates.icon
        if (updates.color !== undefined) patch.color = updates.color
        if (updates.parentId !== undefined) patch.parentId = updates.parentId

        await ctx.db.patch(categoryId, patch)
    },
})

export const deleteCategory = mutation({
    args: {
        categoryId: v.id('categories'),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        const category = await ctx.db.get(args.categoryId)
        if (!category) throw new Error('Category not found')
        if (category.isSystem)
            throw new Error('System categories cannot be deleted')
        if (category.userId !== user._id) throw new Error('Not authorized')

        const otherId = await getOtherCategoryId(ctx)

        // Reassign transactions to "Other"
        const transactions = await ctx.db
            .query('transactions')
            .withIndex('by_userId_and_categoryId', (q) =>
                q.eq('userId', user._id).eq('categoryId', args.categoryId),
            )
            .take(500)

        for (const tx of transactions) {
            await ctx.db.patch(tx._id, { categoryId: otherId ?? undefined })
        }

        // Promote children to top-level
        const children = await ctx.db
            .query('categories')
            .withIndex('by_parentId', (q) => q.eq('parentId', args.categoryId))
            .take(50)

        for (const child of children) {
            await ctx.db.patch(child._id, { parentId: undefined })
        }

        await ctx.db.delete(args.categoryId)
    },
})

export const seedSystemCategories = mutation({
    args: {},
    handler: async (ctx) => {
        // Check if already seeded
        const existing = await ctx.db
            .query('categories')
            .withIndex('by_isSystem', (q) => q.eq('isSystem', true))
            .first()
        if (existing) return

        for (const cat of SYSTEM_CATEGORIES) {
            await ctx.db.insert('categories', {
                name: cat.name,
                icon: cat.icon,
                color: cat.color,
                isSystem: true,
                sortOrder: cat.sortOrder,
            })
        }
    },
})
