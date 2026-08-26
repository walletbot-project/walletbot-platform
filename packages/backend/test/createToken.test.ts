// Unit tests for the mint's prompt assembly — outside convex/ so the Convex
// bundler never sees them. Everything under test is pure (no ctx, no fetch).

import { AGENT_CONTEXT_CAPS, TOOL_NAMES } from '@wallet-bot/shared'
import { describe, expect, it } from 'vitest'
import {
    buildSystemInstruction,
    declarationsFor,
    renderUserContext,
} from '../convex/live/createToken'

// Every flag-gated tool switched on, i.e. what a fully rolled-out user gets.
const ALL_FLAGS = { exchangeRates: true } as const

describe('declarationsFor (compatibility gating)', () => {
    it('web is unrestricted by version', () => {
        expect(
            declarationsFor('web', '0.0.0', ALL_FLAGS).map((d) => d.name),
        ).toEqual(TOOL_NAMES)
    })

    it('an old native build never sees tools it cannot execute', () => {
        const names = declarationsFor('android', '0.2.0').map((d) => d.name)
        expect(names).not.toContain('summarizeTransactions')
        expect(names).toContain('listTransactions')
    })

    it('a current native build sees the full set', () => {
        expect(
            declarationsFor('android', '0.3.1', ALL_FLAGS).map((d) => d.name),
        ).toEqual(TOOL_NAMES)
    })

    it('a 0.3.0 native build never sees the calculator tools', () => {
        const names = declarationsFor('android', '0.3.0').map((d) => d.name)
        expect(names).not.toContain('calculate')
        expect(names).not.toContain('calculateDate')
        expect(names).toContain('readSkill')
    })

    it('a missing platform/version fails closed to the ungated set', () => {
        const names = declarationsFor(undefined, undefined).map((d) => d.name)
        expect(names).not.toContain('summarizeTransactions')
    })

    it('a flag-gated tool is off unless the flag says otherwise', () => {
        // Default (no flags resolved) and an explicit false both withhold it,
        // on every platform — the flag gate is not a version gate.
        expect(
            declarationsFor('web', '9.9.9').map((d) => d.name),
        ).not.toContain('getExchangeRate')
        expect(
            declarationsFor('web', '9.9.9', { exchangeRates: false }).map(
                (d) => d.name,
            ),
        ).not.toContain('getExchangeRate')
        expect(
            declarationsFor('android', '0.3.1', ALL_FLAGS).map((d) => d.name),
        ).toContain('getExchangeRate')
    })

    it('the flag cannot hand a tool to a native build that lacks the executor', () => {
        // Both gates apply: flag on, binary too old.
        expect(
            declarationsFor('android', '0.3.0', ALL_FLAGS).map((d) => d.name),
        ).not.toContain('getExchangeRate')
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

    it('closes the suggestion list to widgets, tags and cosmetics', () => {
        const prompt = buildSystemInstruction({})
        expect(prompt).toContain('exactly THREE things')
        // Half-built surfaces the model would otherwise volunteer on its own.
        expect(prompt).toContain(
            'Recurring or scheduled movements DO NOT EXIST',
        )
        expect(prompt).toContain('Saved filters have no screen of their own')
        expect(prompt).toContain('Read the suggesting-features skill')
    })

    it('lets cosmetics be offered after creation but never before', () => {
        const prompt = buildSystemInstruction({})
        expect(prompt).toContain(
            'NEVER ask what color or icon to use before or while creating one',
        )
        expect(prompt).toContain('you MAY offer to add one')
        expect(prompt).toContain('tags take a color only')
    })

    it('redirects balance patching to addBalanceAdjustment', () => {
        const prompt = buildSystemInstruction({})
        expect(prompt).toContain(
            'record that with addBalanceAdjustment instead',
        )
        expect(prompt).toContain("never counts as the session's one suggestion")
    })

    it('platform notes match the connecting client', () => {
        expect(buildSystemInstruction({ platform: 'android' })).toContain(
            'native mobile app',
        )
        expect(buildSystemInstruction({ platform: 'web' })).toContain('web app')
    })

    it('the math guide only appears when the calculator tools are declared', () => {
        expect(buildSystemInstruction({ platform: 'web' })).toContain('# Math')
        expect(
            buildSystemInstruction({
                platform: 'android',
                appVersion: '0.3.1',
            }),
        ).toContain('# Math')
        // A binary without the executors must not be told about the tools.
        expect(
            buildSystemInstruction({
                platform: 'android',
                appVersion: '0.3.0',
            }),
        ).not.toContain('# Math')
        expect(buildSystemInstruction({})).not.toContain('# Math')
    })

    it('the exchange-rate guide follows the tool, not the platform', () => {
        expect(
            buildSystemInstruction({ platform: 'web', flags: ALL_FLAGS }),
        ).toContain('# Exchange rates')
        // Flag off, or a binary without the executor: never mention the tool.
        expect(buildSystemInstruction({ platform: 'web' })).not.toContain(
            '# Exchange rates',
        )
        expect(
            buildSystemInstruction({
                platform: 'android',
                appVersion: '0.3.0',
                flags: ALL_FLAGS,
            }),
        ).not.toContain('# Exchange rates')
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
