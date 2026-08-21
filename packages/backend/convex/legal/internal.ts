import { isValidLegalVersion } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'
import { CURRENT_LEGAL_VERSION, recordAcceptance } from './helpers'

/**
 * Signup-time acceptance, invoked from better-auth's user-create hook and the
 * native auth endpoints. A failure here must never break account creation:
 * the post-auth gate re-prompts any account that ends up without a record.
 *
 * The version is client-supplied, so it is clamped to documents that actually
 * exist: a value above the one in force is dropped. Accepting it would be both
 * false evidence (nobody agreed to unwritten terms) and a permanent exemption
 * — `legalVerdict` clears anything `>= current`, so a client claiming
 * `9999-12-31` would never be gated again. Older versions ARE recorded: the
 * user did agree to that text, and the gate re-prompts them for the new one.
 */
export const recordSignupAcceptance = internalMutation({
    args: {
        userId: v.string(),
        documentVersion: v.string(),
    },
    handler: async (ctx, args) => {
        try {
            if (
                !isValidLegalVersion(args.documentVersion) ||
                args.documentVersion > CURRENT_LEGAL_VERSION
            ) {
                console.warn('legal: ignoring unusable documentVersion', {
                    userId: args.userId,
                    documentVersion: args.documentVersion,
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
