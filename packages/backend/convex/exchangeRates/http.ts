import type { HttpRouter } from 'convex/server'
import { internal } from '../_generated/api'
import { httpAction } from '../_generated/server'
import { jsonResponse, preflightResponse } from '../httpHelpers'

// GET /v1/fx/rates
//
// The market-rate snapshot for the native agent's `getExchangeRate` tool.
// Unauthenticated by design: it is public market data with no user data in the
// request or the response, and native tool executors must never hold a Convex
// client (they run offline against the local database). The device caches the
// last good response, so a failure here degrades to a stale-but-honest quote
// rather than an error.
const getRates = httpAction(async (ctx) => {
    const rates = await ctx.runQuery(internal.exchangeRates.internal.snapshot)
    return jsonResponse({ rates })
})

export const registerExchangeRateRoutes = (http: HttpRouter): void => {
    http.route({ path: '/v1/fx/rates', method: 'GET', handler: getRates })
    http.route({
        path: '/v1/fx/rates',
        method: 'OPTIONS',
        handler: httpAction(async () => preflightResponse()),
    })
}
