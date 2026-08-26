import { query } from '../../_generated/server'
import { requireAuth } from '../../users/helpers'
import { getSettingsForUser } from './helpers'

/**
 * `language` is additive: it is `null` until a client reports one, and builds
 * that predate the field ignore it. Clients read it back to tell whether their
 * report landed, never to drive the in-app display language.
 */
export const getSettings = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        return await getSettingsForUser(ctx, userId)
    },
})

/**
 * The authenticated user's id — the value every `userId` column holds.
 *
 * Web needs it to fill the `ownerId` assertion on
 * `v1/voice/sessions:appendEvents`: the mutation rejects a mismatch, which is
 * the guard that stops an in-flight batch from crossing account boundaries. It
 * is derived server-side, so a client cannot claim someone else's history.
 */
export const getMyId = query({
    args: {},
    handler: async (ctx) => await requireAuth(ctx),
})
