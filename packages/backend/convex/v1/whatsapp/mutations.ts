import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import { resolveFlagsForUser } from '../../featureFlags/helpers'
import { resolveAiConsent } from '../../legal/helpers'
import { requireAuth } from '../../users/helpers'
import {
    buildLinkDeepLink,
    formatLinkCode,
    generateLinkCode,
    LINK_CODE_TTL_MS,
} from '../../whatsapp/linking'

// How many of a user's codes to scan when looking for a live one to reuse.
// Codes are short-lived and purged hourly, so a user never accumulates many.
const USER_CODE_SCAN = 16

// Bound on linked numbers touched per unlink. Nobody links this many phones;
// the cap exists so the mutation stays a bounded read.
const LINKED_NUMBER_SCAN = 16

// Don't hand back a code that is about to expire — the user still has to open
// WhatsApp and send it.
const REUSE_MIN_REMAINING_MS = 60 * 1000

// Mints the code a user sends over WhatsApp to link their number.
//
// This is the authenticated half of the link flow: it must be callable only by
// a logged-in session, because possessing the code is what proves to the
// webhook — which has no authentication of its own — that the person messaging
// the business number owns this account.
export const createLinkCode = mutation({
    args: {
        /**
         * The calling client's platform, for the iOS AI-consent check below.
         * Optional: builds that predate the check send nothing, and web never
         * sends 'ios'.
         */
        platform: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        // The rollout gate, enforced where it matters: a code is the thing
        // that grants a phone number access to this account, so an account
        // outside the rollout must not be able to mint one even if a client
        // asks anyway.
        const flags = await resolveFlagsForUser(ctx, userId)
        if (!flags.whatsapp) {
            throw new Error('WhatsApp is not available for this account')
        }
        // Backstop for the client-side sheet, same as the live mint. Linking
        // is the last authenticated step before inbound messages start running
        // the agent server-side, where there is no device left to ask. iOS
        // only, by product decision.
        if (args.platform === 'ios' && flags.aiConsent === true) {
            const consent = await resolveAiConsent(ctx, userId)
            if (!consent.accepted) {
                throw new Error('AI consent is required before linking')
            }
        }
        const now = Date.now()

        const existing = await ctx.db
            .query('whatsappLinkCodes')
            .withIndex('by_userId', (q) => q.eq('userId', userId))
            .take(USER_CODE_SCAN)

        // Reuse a live code so repeated taps on "connect WhatsApp" don't leave
        // a trail of valid codes, each of which is a way into the account.
        const live = existing.find(
            (row) =>
                row.consumedAt === undefined &&
                row.expiresAt > now + REUSE_MIN_REMAINING_MS,
        )
        if (live) {
            return {
                code: formatLinkCode(live.code),
                expiresAt: live.expiresAt,
                deepLink: buildLinkDeepLink(
                    process.env.WHATSAPP_BUSINESS_NUMBER,
                    live.code,
                ),
            }
        }

        // Uniqueness is enforced here rather than trusted from randomness, so
        // the `by_code` lookup in tryLink can use `.unique()` and a collision
        // can never make one user's code resolve to another user's account.
        let code: string | null = null
        for (let attempt = 0; attempt < 8; attempt += 1) {
            const candidate = generateLinkCode()
            const clash = await ctx.db
                .query('whatsappLinkCodes')
                .withIndex('by_code', (q) => q.eq('code', candidate))
                .first()
            if (!clash) {
                code = candidate
                break
            }
        }
        if (code === null) {
            throw new Error('could not allocate a unique link code')
        }

        const expiresAt = now + LINK_CODE_TTL_MS
        await ctx.db.insert('whatsappLinkCodes', {
            code,
            userId,
            createdAt: now,
            expiresAt,
        })

        return {
            code: formatLinkCode(code),
            expiresAt,
            deepLink: buildLinkDeepLink(
                process.env.WHATSAPP_BUSINESS_NUMBER,
                code,
            ),
        }
    },
})

// Disconnects one linked number, or every one when `waId` is omitted.
//
// Deliberately NOT gated by the `whatsapp` flag. Turning a rollout off must
// never leave someone with a number linked to their account and no way to
// remove it; taking the capability away is not the same as taking away the
// undo for it.
//
// Ownership is resolved from the session, never from the argument: a `waId` is
// a public phone identifier, so accepting one as authorization would let any
// authenticated user unlink someone else's number.
export const unlink = mutation({
    args: { waId: v.optional(v.string()) },
    handler: async (ctx, { waId }) => {
        const userId = await requireAuth(ctx)

        const linked = await ctx.db
            .query('whatsappConversations')
            .withIndex('by_userId', (q) => q.eq('userId', userId))
            .take(LINKED_NUMBER_SCAN)

        const targets =
            waId === undefined
                ? linked
                : linked.filter((conversation) => conversation.waId === waId)

        for (const conversation of targets) {
            await ctx.db.patch(conversation._id, {
                userId: undefined,
                linkedAt: undefined,
                failedLinkAttempts: undefined,
                linkBlockedUntil: undefined,
            })
        }

        // Unconsumed codes are revoked too. Otherwise a code minted before the
        // unlink would still be live and could silently re-link the number the
        // user just disconnected.
        const codes = await ctx.db
            .query('whatsappLinkCodes')
            .withIndex('by_userId', (q) => q.eq('userId', userId))
            .take(USER_CODE_SCAN)
        for (const row of codes) {
            if (row.consumedAt === undefined) await ctx.db.delete(row._id)
        }

        return { unlinked: targets.length }
    },
})
