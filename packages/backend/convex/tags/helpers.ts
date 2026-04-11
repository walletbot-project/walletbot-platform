import type { Id } from '../_generated/dataModel'
import type { MutationCtx } from '../_generated/server'

/**
 * Resolve tag names to IDs. Creates tags that don't exist yet.
 * Used by voice integration: "tag it as vacation" auto-creates the tag.
 */
export async function resolveTagIds(
    ctx: MutationCtx,
    userId: string,
    names: string[],
): Promise<Id<'tags'>[]> {
    const ids: Id<'tags'>[] = []

    for (const rawName of names) {
        const name = rawName.trim().toLowerCase()
        if (!name) continue

        const existing = await ctx.db
            .query('tags')
            .withIndex('by_userId_and_name', (q) =>
                q.eq('userId', userId).eq('name', name),
            )
            .first()

        if (existing) {
            ids.push(existing._id)
        } else {
            // Auto-create with a neutral color
            const id = await ctx.db.insert('tags', {
                userId,
                name,
                color: '#6b7280',
            })
            ids.push(id)
        }
    }

    return ids
}
