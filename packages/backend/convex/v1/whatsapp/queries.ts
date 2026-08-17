import { query } from '../../_generated/server'
import { requireAuth } from '../../users/helpers'

// A user is not expected to link many numbers; this bound keeps the read cheap
// while still covering every realistic case.
const MAX_LINKED_NUMBERS = 16

// Which WhatsApp numbers are connected to the caller's account.
//
// `waId` is returned in full because it is the caller's own number — they are
// the one party entitled to see it. Masking for display is the client's call.
export const linkStatus = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)

        const linked = await ctx.db
            .query('whatsappConversations')
            .withIndex('by_userId', (q) => q.eq('userId', userId))
            .take(MAX_LINKED_NUMBERS)

        return {
            // False when the deployment has no business number configured, so
            // the client can hide the entry point instead of offering a flow
            // that cannot complete.
            available:
                typeof process.env.WHATSAPP_BUSINESS_NUMBER === 'string' &&
                process.env.WHATSAPP_BUSINESS_NUMBER.length > 0,
            businessNumber: process.env.WHATSAPP_BUSINESS_NUMBER ?? null,
            numbers: linked.map((conversation) => ({
                waId: conversation.waId,
                linkedAt: conversation.linkedAt ?? null,
            })),
        }
    },
})
