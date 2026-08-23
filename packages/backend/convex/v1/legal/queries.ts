import { query } from '../../_generated/server'
import { resolveAcceptanceStatus } from '../../legal/helpers'
import { requireAuth } from '../../users/helpers'

/**
 * What the signed-in user still owes on the Terms and the Privacy Policy.
 *
 * Drives the acceptance gate on both clients: `blocking` means no way past it
 * but signing out, `prompt` without `blocking` means the grace period is still
 * running and the prompt can be dismissed. Per-document `status` is what the
 * copy keys off, so the gate can name only the document that actually changed.
 */
export const acceptanceStatus = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        return await resolveAcceptanceStatus(ctx, userId)
    },
})
