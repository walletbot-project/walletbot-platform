import { query } from './_generated/server'

// Cheap unauthenticated query used by convex_flutter's `reconnect()` health
// check and by client-side watchdogs. Must stay trivial so it round-trips
// fast and doesn't fail under load.
export const ping = query({
    args: {},
    handler: async () => true,
})
