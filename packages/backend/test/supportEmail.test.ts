// Unit tests for the inbound support-mail rules, outside convex/ so the Convex
// bundler never sees them. Everything under test is pure (no ctx, no fetch):
// the recipient filter that scopes the pipeline to the support mailboxes, the
// loop guard, and the body truncation that keeps a row under Convex's 1 MiB
// document limit.

import { describe, expect, it } from 'vitest'
import {
    capBodies,
    extractAddress,
    isForwardLoop,
    isSupportRecipient,
    parseTimestamp,
    truncateToBytes,
} from '../convex/support/utils'

const envelope = (overrides: {
    to?: string[]
    cc?: string[]
    bcc?: string[]
    received_for?: string[]
}) => ({
    to: overrides.to ?? [],
    cc: overrides.cc ?? [],
    bcc: overrides.bcc ?? [],
    received_for: overrides.received_for ?? [],
})

describe('extractAddress', () => {
    it('pulls the address out of a display-name header', () => {
        expect(extractAddress('Ada Lovelace <ada@example.com>')).toBe(
            'ada@example.com',
        )
    })

    it('passes a bare address through, lowercased and trimmed', () => {
        expect(extractAddress('  Ada@Example.COM ')).toBe('ada@example.com')
    })
})

describe('isSupportRecipient', () => {
    it('accepts the address of record', () => {
        expect(
            isSupportRecipient(envelope({ to: ['support@walletbot.live'] })),
        ).toBe(true)
    })

    it('accepts the Spanish spelling of the same mailbox', () => {
        expect(
            isSupportRecipient(envelope({ to: ['soporte@walletbot.live'] })),
        ).toBe(true)
    })

    it('accepts a display-name header', () => {
        expect(
            isSupportRecipient(
                envelope({ to: ['Wallet Bot <SUPPORT@walletbot.live>'] }),
            ),
        ).toBe(true)
    })

    it('accepts a blind copy, which never shows up in to or cc', () => {
        expect(
            isSupportRecipient(
                envelope({
                    to: ['someone@example.com'],
                    bcc: ['support@walletbot.live'],
                }),
            ),
        ).toBe(true)
    })

    it('accepts a relayed message that only carries the address in received_for', () => {
        expect(
            isSupportRecipient(
                envelope({
                    to: ['forwarded@example.com'],
                    received_for: ['support@walletbot.live'],
                }),
            ),
        ).toBe(true)
    })

    // MX records make Resend accept mail for every address at the domain, so
    // this is what keeps the table from absorbing the whole domain's spam.
    it('rejects another mailbox at the same domain', () => {
        expect(
            isSupportRecipient(envelope({ to: ['billing@walletbot.live'] })),
        ).toBe(false)
    })

    it('rejects a lookalike address at another domain', () => {
        expect(
            isSupportRecipient(
                envelope({ to: ['support@walletbot.live.evil.com'] }),
            ),
        ).toBe(false)
    })
})

describe('isForwardLoop', () => {
    it('refuses mail sent from the support mailbox itself', () => {
        expect(
            isForwardLoop('support@walletbot.live', 'group@googlegroups.com'),
        ).toBe(true)
    })

    it('refuses mail sent from the forwarding destination', () => {
        expect(
            isForwardLoop(
                'Group <group@googlegroups.com>',
                'group@googlegroups.com',
            ),
        ).toBe(true)
    })

    it('forwards mail from anyone else', () => {
        expect(isForwardLoop('ada@example.com', 'group@googlegroups.com')).toBe(
            false,
        )
    })
})

describe('truncateToBytes', () => {
    it('leaves a string that already fits untouched', () => {
        expect(truncateToBytes('hola', 16)).toBe('hola')
    })

    it('counts UTF-8 bytes, not characters', () => {
        // 'é' is two bytes, so four of them exceed a six-byte budget.
        expect(truncateToBytes('éééé', 6)).toBe('ééé')
    })

    it('never returns more than the budget', () => {
        const cjk = '想'.repeat(1000)
        const cut = truncateToBytes(cjk, 100)
        expect(new TextEncoder().encode(cut).length).toBeLessThanOrEqual(100)
    })

    it('does not split a surrogate pair into a lone surrogate', () => {
        // Each emoji is one astral character: two UTF-16 units, four bytes.
        const cut = truncateToBytes('🙂🙂🙂', 6)
        expect(cut).toBe('🙂')
        expect(cut).not.toMatch(/[\uD800-\uDBFF]$/)
    })

    it('returns an empty string when even one character does not fit', () => {
        expect(truncateToBytes('🙂', 2)).toBe('')
    })
})

describe('capBodies', () => {
    it('reports nothing truncated for small bodies', () => {
        expect(capBodies('<p>hola</p>', 'hola')).toEqual({
            html: '<p>hola</p>',
            text: 'hola',
            truncated: false,
        })
    })

    it('keeps nulls as nulls', () => {
        expect(capBodies(null, null)).toEqual({
            html: null,
            text: null,
            truncated: false,
        })
    })

    // The whole point of the byte budget: a body this size in characters used
    // to pass a character-based cap and then fail the insert.
    it('truncates a multi-byte body that would blow the document limit', () => {
        const huge = '想'.repeat(600 * 1024)
        const capped = capBodies(huge, null)
        expect(capped.truncated).toBe(true)
        expect(
            new TextEncoder().encode(capped.html ?? '').length,
        ).toBeLessThanOrEqual(512 * 1024)
    })

    it('flags truncation when only the text body is over', () => {
        const capped = capBodies('<p>hola</p>', 'a'.repeat(200 * 1024))
        expect(capped.truncated).toBe(true)
        expect(capped.html).toBe('<p>hola</p>')
        expect(capped.text).toHaveLength(128 * 1024)
    })
})

describe('parseTimestamp', () => {
    it('parses an ISO timestamp', () => {
        expect(parseTimestamp('2026-08-25T12:00:00.000Z', 123)).toBe(
            Date.parse('2026-08-25T12:00:00.000Z'),
        )
    })

    // An unparseable timestamp must not abort archiving a valid email.
    it('falls back to now when the timestamp is unusable', () => {
        expect(parseTimestamp('not a date', 123)).toBe(123)
    })
})
