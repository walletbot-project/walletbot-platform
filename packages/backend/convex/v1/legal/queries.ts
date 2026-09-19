import { query } from '../../_generated/server'
import { resolveAcceptanceStatus, resolveAiConsent } from '../../legal/helpers'
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

/**
 * Whether the signed-in user has consented to sending their data to the AI
 * providers, at the current disclosure version.
 *
 * Separate from `acceptanceStatus` on purpose: this consent is asked for at
 * the point of use (before the first agent session), not at the launch gate.
 */
export const aiConsentStatus = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        return await resolveAiConsent(ctx, userId)
    },
})
