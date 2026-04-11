import type { Id } from '../_generated/dataModel'
import type { MutationCtx, QueryCtx } from '../_generated/server'

/**
 * System category definitions. Seeded once on first use.
 * `name` is an i18n key — the frontend resolves it to the display string.
 */
export const SYSTEM_CATEGORIES = [
    // Expense categories
    {
        name: 'categories.system.groceries',
        icon: '🛒',
        color: '#22c55e',
        sortOrder: 0,
    },
    {
        name: 'categories.system.transport',
        icon: '🚗',
        color: '#3b82f6',
        sortOrder: 1,
    },
    {
        name: 'categories.system.dining',
        icon: '🍽️',
        color: '#f97316',
        sortOrder: 2,
    },
    {
        name: 'categories.system.entertainment',
        icon: '🎬',
        color: '#a855f7',
        sortOrder: 3,
    },
    {
        name: 'categories.system.utilities',
        icon: '💡',
        color: '#eab308',
        sortOrder: 4,
    },
    {
        name: 'categories.system.health',
        icon: '🏥',
        color: '#ef4444',
        sortOrder: 5,
    },
    {
        name: 'categories.system.shopping',
        icon: '🛍️',
        color: '#ec4899',
        sortOrder: 6,
    },
    {
        name: 'categories.system.other',
        icon: '📦',
        color: '#6b7280',
        sortOrder: 7,
    },
    // Income categories
    {
        name: 'categories.system.salary',
        icon: '💰',
        color: '#10b981',
        sortOrder: 8,
    },
    {
        name: 'categories.system.freelance',
        icon: '💻',
        color: '#06b6d4',
        sortOrder: 9,
    },
    {
        name: 'categories.system.investment',
        icon: '📈',
        color: '#8b5cf6',
        sortOrder: 10,
    },
    {
        name: 'categories.system.gift',
        icon: '🎁',
        color: '#f43f5e',
        sortOrder: 11,
    },
] as const

/**
 * Map from old string category names to i18n keys.
 * Used for migrating existing expenses.
 */
export const LEGACY_CATEGORY_MAP: Record<string, string> = {
    groceries: 'categories.system.groceries',
    transport: 'categories.system.transport',
    dining: 'categories.system.dining',
    entertainment: 'categories.system.entertainment',
    utilities: 'categories.system.utilities',
    health: 'categories.system.health',
    shopping: 'categories.system.shopping',
    other: 'categories.system.other',
}

/**
 * Find a category by name or ID for the given user.
 * Searches user's categories first, then system categories.
 */
export async function resolveCategoryId(
    ctx: QueryCtx | MutationCtx,
    userId: string,
    nameOrId: string,
): Promise<Id<'categories'> | null> {
    // Try as ID first
    const normalized = ctx.db.normalizeId('categories', nameOrId)
    if (normalized) {
        const cat = await ctx.db.get(normalized)
        if (cat && (cat.userId === userId || cat.isSystem)) return normalized
    }

    // Search by name — user categories first
    const userCats = await ctx.db
        .query('categories')
        .withIndex('by_userId', (q) => q.eq('userId', userId))
        .take(100)

    const lowerName = nameOrId.toLowerCase().trim()
    const userMatch = userCats.find((c) => c.name.toLowerCase() === lowerName)
    if (userMatch) return userMatch._id

    // Then system categories
    const systemCats = await ctx.db
        .query('categories')
        .withIndex('by_isSystem', (q) => q.eq('isSystem', true))
        .take(50)

    const systemMatch = systemCats.find(
        (c) =>
            c.name.toLowerCase() === lowerName ||
            c.name === `categories.system.${lowerName}`,
    )
    if (systemMatch) return systemMatch._id

    return null
}

/**
 * Get the "Other" system category ID. Used as fallback.
 */
export async function getOtherCategoryId(
    ctx: QueryCtx | MutationCtx,
): Promise<Id<'categories'> | null> {
    const systemCats = await ctx.db
        .query('categories')
        .withIndex('by_isSystem', (q) => q.eq('isSystem', true))
        .take(50)

    const other = systemCats.find((c) => c.name === 'categories.system.other')
    return other?._id ?? null
}
