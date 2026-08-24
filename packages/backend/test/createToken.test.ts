// Unit tests for the mint's prompt assembly — outside convex/ so the Convex
// bundler never sees them. Everything under test is pure (no ctx, no fetch).

import { AGENT_CONTEXT_CAPS, TOOL_NAMES } from '@wallet-bot/shared'
import { describe, expect, it } from 'vitest'
import {
    buildSystemInstruction,
    declarationsFor,
    renderUserContext,
} from '../convex/live/createToken'

describe('declarationsFor (compatibility gating)', () => {
    it('web is unrestricted', () => {
        expect(declarationsFor('web', '0.0.0').map((d) => d.name)).toEqual(
            TOOL_NAMES,
        )
    })

    it('an old native build never sees tools it cannot execute', () => {
        const names = declarationsFor('android', '0.2.0').map((d) => d.name)
        expect(names).not.toContain('summarizeTransactions')
        expect(names).toContain('listTransactions')
    })

    it('a current native build sees the full set', () => {
        expect(declarationsFor('android', '0.3.0').map((d) => d.name)).toEqual(
            TOOL_NAMES,
        )
    })

    it('a missing platform/version fails closed to the ungated set', () => {
        const names = declarationsFor(undefined, undefined).map((d) => d.name)
        expect(names).not.toContain('summarizeTransactions')
    })
})

describe('renderUserContext', () => {
    it('returns null for an empty payload', () => {
        expect(renderUserContext({})).toBeNull()
    })

    it('renders every section it is given', () => {
        const block = renderUserContext({
            userName: 'Tomás',
            userEmail: 'tomas@example.com',
            settings: { defaultCurrency: 'ARS', language: 'es', theme: 'dark' },
            accounts: [{ id: 'a1', name: 'Efectivo', currency: 'ARS' }],
            categories: [{ id: 'c1', name: 'Food' }],
            tags: [{ id: 't1', name: 'Work' }],
            recentTransactions: [
                {
                    name: 'Starbucks',
                    amount: 12.5,
                    currency: 'ARS',
                    type: 'expense',
                    account: 'Efectivo',
                    category: 'Food',
                    date: '2026-08-23 14:30',
                },
            ],
            memories: [{ id: 'm1', content: 'Prefers Galicia by default' }],
        })
        expect(block).not.toBeNull()
        expect(block).toContain('Snapshot taken when the session started')
        expect(block).toContain('Tomás — tomas@example.com')
        expect(block).toContain('default currency ARS')
        expect(block).toContain('Efectivo [ARS, id a1]')
        expect(block).toContain('Food [id c1]')
        expect(block).toContain('Work [id t1]')
        expect(block).toContain('expense 12.50 ARS "Starbucks"')
        expect(block).toContain('[m1] Prefers Galicia by default')
    })

    it('truncates an oversized block with an explicit marker', () => {
        const memories = Array.from({ length: 200 }, (_, i) => ({
            id: `m${i}`,
            content: 'x'.repeat(400),
        }))
        const block = renderUserContext({ memories })
        expect(block).not.toBeNull()
        expect(block?.length).toBeLessThanOrEqual(
            AGENT_CONTEXT_CAPS.maxSerializedChars + 300,
        )
        expect(block).toContain('[Context truncated')
    })
})

describe('buildSystemInstruction', () => {
    it('a bare mint (old build) gets the base prompt without USER_CONTEXT', () => {
        const prompt = buildSystemInstruction({})
        expect(prompt).toContain('You are Gaston')
        expect(prompt).not.toContain('Current data snapshot')
        expect(prompt).toMatch(/Today is /)
    })

    it('carries the gentle feature-discovery rules with the memory opt-out', () => {
        const prompt = buildSystemInstruction({})
        expect(prompt).toContain('Suggesting features (gently)')
        expect(prompt).toContain('At most one suggestion per session')
        expect(prompt).toContain(
            "Don't suggest app features — the user knows the app",
        )
    })

    it('platform notes match the connecting client', () => {
        expect(buildSystemInstruction({ platform: 'android' })).toContain(
            'native mobile app',
        )
        expect(buildSystemInstruction({ platform: 'web' })).toContain('web app')
    })

    it('an oversized, hostile payload is capped, not rejected', () => {
        const prompt = buildSystemInstruction({
            platform: 'web',
            locale: 'es-AR',
            timezone: 'America/Argentina/Buenos_Aires',
            context: {
                accounts: Array.from({ length: 5000 }, (_, i) => ({
                    id: `a${i}`,
                    name: 'x'.repeat(10_000),
                    currency: 'ARS',
                })),
                nonsense: { deeply: ['ignored'] },
            },
        })
        expect(prompt).toContain('Current data snapshot')
        // 5000 accounts with 10k-char names must not survive the caps.
        expect(prompt.length).toBeLessThan(
            AGENT_CONTEXT_CAPS.maxSerializedChars + 20_000,
        )
    })

    it('the date line survives an unknown timezone and a broken offset', () => {
        expect(buildSystemInstruction({ timezone: 'Not/AZone' })).toMatch(
            /Today is /,
        )
        expect(
            buildSystemInstruction({ timezoneOffsetMinutes: 99999 }),
        ).toMatch(/Today is /)
    })

    it('the date line is computed in the client timezone', () => {
        // 14 hours apart guarantees the two renders differ for at least part
        // of every day; assert they are both present rather than pinning a
        // wall-clock value to the test machine's clock.
        const west = buildSystemInstruction({
            locale: 'en-US',
            timezoneOffsetMinutes: -12 * 60,
        })
        const east = buildSystemInstruction({
            locale: 'en-US',
            timezoneOffsetMinutes: 14 * 60,
        })
        expect(west).toMatch(/Today is [A-Z]/)
        expect(east).toMatch(/Today is [A-Z]/)
    })
})
