import type { QueryCtx } from '../_generated/server'
import { authComponent } from '../auth'

export async function requireUserId(ctx: QueryCtx): Promise<string> {
    const user = await authComponent.getAuthUser(ctx)
    if (!user) throw new Error('Unauthenticated')
    return user._id
}
