// The `whatsapp` rollout flag and the copy that goes with it. Pure — the
// gating itself lives in Convex functions, which these cannot reach; what they
// pin is the contract those functions read.

import { describe, expect, it } from 'vitest'
import { isKnownFlagKey, KNOWN_FLAGS } from '../convex/featureFlags/utils'
import { disabledReplyText, linkReplyText } from '../convex/whatsapp/linking'

describe('the whatsapp flag', () => {
    it('is registered and off by default', () => {
        const flag = KNOWN_FLAGS.find((entry) => entry.key === 'whatsapp')
        expect(flag).toBeDefined()
        // A number linked to an account is a standing grant of access to that
        // account's money. Nobody gets that by being in the wrong percentile
        // of a default-on rollout.
        expect(flag?.enabledByDefault).toBe(false)
        expect(isKnownFlagKey('whatsapp')).toBe(true)
    })
})

describe('disabledReplyText', () => {
    it('answers in both languages, and differently', () => {
        expect(disabledReplyText('es')).not.toBe('')
        expect(disabledReplyText('en')).not.toBe('')
        expect(disabledReplyText('es')).not.toBe(disabledReplyText('en'))
    })

    it('says nothing about the account it could not serve', () => {
        // The number reaching us is not proof of who owns it, and this line is
        // sent to a linked conversation whose rollout was switched off. It
        // must not leak anything about the account behind the link.
        for (const language of ['es', 'en'] as const) {
            const text = disabledReplyText(language)
            expect(text).not.toMatch(/@/)
            expect(text.length).toBeLessThan(200)
        }
    })

    it('is not the same line a blocked sender gets, which is silence', () => {
        expect(
            linkReplyText({ kind: 'blocked', until: 0 }, 'es'),
            'a blocked conversation still gets no reply at all',
        ).toBeNull()
    })
})
