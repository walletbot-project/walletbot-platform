import { isValidLegalVersion } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'
import { recordAcceptance } from './helpers'

/**
 * Signup-time acceptance, invoked from better-auth's user-create hook and the
 * native auth endpoints. A failure here must never break account creation:
 * the post-auth gate re-prompts any account that ends up without a record.
 */
export const recordSignupAcceptance = internalMutation({
    args: {
        userId: v.string(),
        documentVersion: v.string(),
    },
    handler: async (ctx, args) => {
        try {
            if (!isValidLegalVersion(args.documentVersion)) {
                console.warn('legal: ignoring malformed documentVersion', {
                    userId: args.userId,
                })
                return null
            }
            await recordAcceptance(ctx, {
                userId: args.userId,
                documentVersion: args.documentVersion,
                source: 'signup',
            })
        } catch (error) {
            console.error('legal: signup acceptance recording failed', {
                userId: args.userId,
                error: error instanceof Error ? error.message : String(error),
            })
        }
        return null
    },
})
