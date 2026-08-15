import { query } from '../../_generated/server'
import { requireAuth } from '../../users/helpers'
import { getDefaultCurrency } from './helpers'

export const getSettings = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        return { defaultCurrency: await getDefaultCurrency(ctx, userId) }
    },
})
