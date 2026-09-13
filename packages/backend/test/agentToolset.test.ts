// Unit tests for the text agent's tool list and prompt assembly — outside
// convex/ so the Convex bundler never sees them. Everything under test is pure
// (no ctx, no fetch).

import { TOOL_MAP, TOOL_NAMES } from '@wallet-bot/shared'
import { describe, expect, it } from 'vitest'
import { buildTextSystemInstruction } from '../convex/agent/prompt'
import {
    AGENT_TOOL_NAMES,
    flagForTool,
    isAgentToolName,
    toolDefinitionsFor,
} from '../convex/agent/toolset'

const NOW = Date.UTC(2026, 7, 30, 15, 0)
const BUENOS_AIRES = -180

const prompt = (
    overrides: Partial<Parameters<typeof buildTextSystemInstruction>[0]> = {},
) =>
    buildTextSystemInstruction({
        nowMs: NOW,
        utcOffsetMinutes: BUENOS_AIRES,
        preferredLanguage: 'es',
        defaultCurrency: 'ARS',
        memories: [],
        exchangeRatesEnabled: false,
        ...overrides,
    })

describe('AGENT_TOOL_NAMES', () => {
    // The one that matters: the list is looked up in TOOL_MAP to build the
    // model's declarations, so a name the shared package renamed or dropped
    // used to reach Gemini as `undefined` and take the whole module down at
    // push time. `satisfies readonly ToolName[]` catches it at compile time;
    // this catches it in a run.
    it('names only tools the shared contract still defines', () => {
        for (const name of AGENT_TOOL_NAMES) {
            expect(TOOL_MAP[name], name).toBeDefined()
        }
    })

    it('has no duplicates', () => {
        expect(new Set(AGENT_TOOL_NAMES).size).toBe(AGENT_TOOL_NAMES.length)
    })

    it('withholds dashboard, saved-filter, settings and recurrence tools', () => {
        const missing = TOOL_NAMES.filter(
            (name) => !isAgentToolName(name),
        ).sort()
        expect(missing).toEqual([
            'addRecurrenceOccurrences',
            'archiveDashboardWidget',
            'archiveSavedFilter',
            'createDashboardWidget',
            'createSavedFilter',
            'listDashboardWidgets',
            'listRecurrences',
            'listSavedFilters',
            'listUpcomingTransactions',
            'reorderDashboardWidgets',
            'updateDashboardWidget',
            'updateSavedFilter',
            'updateSettings',
        ])
    })

    it('never offers unsupported series arguments, even with the feature flag on', () => {
        for (const recurringExpense of [false, true]) {
            const defs = toolDefinitionsFor({ recurringExpense })
            for (const name of [
                'addExpense',
                'addIncome',
                'updateTransaction',
                'deleteTransaction',
            ]) {
                const definition = defs.find((d) => d.name === name)
                expect(definition).toBeDefined()
                expect(definition?.parameters.properties).not.toHaveProperty(
                    'recurrence',
                )
                expect(definition?.parameters.properties).not.toHaveProperty(
                    'scope',
                )
            }
        }
        expect(prompt()).not.toContain('recurring-movements:')
    })

    it('gates getExchangeRate behind the exchangeRates flag and nothing else', () => {
        expect(flagForTool('getExchangeRate')).toBe('exchangeRates')
        const gated = AGENT_TOOL_NAMES.filter(
            (name) => flagForTool(name) !== undefined,
        )
        expect(gated).toEqual(['getExchangeRate'])
    })
})

describe('buildTextSystemInstruction', () => {
    it('names the agent the way the rest of the app does', () => {
        expect(prompt()).toContain('You are Gaston')
    })

    it('describes only tools this channel actually declares', () => {
        const text = prompt()
        expect(text).toContain('summarizeTransactions')
        expect(text).not.toContain('createDashboardWidget')
        expect(text).not.toContain('updateSettings')
    })

    it('mentions exchange rates only when the flag is on', () => {
        expect(prompt()).not.toContain('# Exchange rates')
        expect(prompt({ exchangeRatesEnabled: true })).toContain(
            '# Exchange rates',
        )
    })

    it('renders memories with their ids, because the tools take one', () => {
        const text = prompt({
            memories: [{ id: 'mem-1', content: 'Si no digo cuenta, Galicia.' }],
        })
        expect(text).toContain('# Memories (1)')
        expect(text).toContain('- [mem-1] Si no digo cuenta, Galicia.')
    })

    it('leaves the memories block out entirely when there are none', () => {
        expect(prompt()).not.toContain('# Memories')
    })

    it("states today in the user's timezone, not the server's", () => {
        // 15:00 UTC is 12:00 in Buenos Aires, same calendar day.
        expect(prompt()).toContain('Sunday, August 30, 2026, 12:00 local time')
    })

    it('carries the default currency and the fallback language', () => {
        expect(prompt()).toContain("The user's default currency is ARS.")
        expect(prompt()).toContain('default to Spanish')
        expect(prompt({ preferredLanguage: 'en' })).toContain(
            'default to English',
        )
    })
})
