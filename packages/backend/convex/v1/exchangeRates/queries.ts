import { query } from '../../_generated/server'
import { readSnapshot } from '../../exchangeRates/helpers'
import { requireAuth } from '../../users/helpers'

/**
 * The market-rate snapshot the web agent's `getExchangeRate` executor resolves
 * against. Global data (no per-user rows), but still behind auth: only signed
 * in users can drive the agent, and there is no reason to expose it wider from
 * the Convex client surface. Native reads the same snapshot over
 * `GET /v1/fx/rates`.
 */
export const snapshot = query({
    args: {},
    handler: async (ctx) => {
        await requireAuth(ctx)
        return await readSnapshot(ctx)
    },
})
