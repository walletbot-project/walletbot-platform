import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { test } from 'node:test'
import ts from 'typescript'

const loadAgentPricing = async () => {
    const source = await readFile(
        new URL('../convex/telemetry/agentPricing.ts', import.meta.url),
        'utf8',
    )
    const compiled = ts.transpileModule(source, {
        compilerOptions: {
            module: ts.ModuleKind.ESNext,
            target: ts.ScriptTarget.ES2023,
            verbatimModuleSyntax: true,
        },
    }).outputText
    const moduleUrl = `data:text/javascript;base64,${Buffer.from(compiled).toString('base64')}`
    return await import(moduleUrl)
}

const baseMetric = {
    name: 'agent.interaction.cost_usd',
    timestamp: Date.parse('2026-08-23T12:00:00.000Z'),
    source: 'native',
    type: 'gauge',
    value: 999,
    unit: 'usd',
    attributes: {
        model: 'gemini-3.1-flash-live-preview',
        mode: 'voice',
        cost_source: 'reconciled',
    },
}

test('recalculates Gemini Live cost from token attributes server-side', async () => {
    const { normalizeAgentCostMetric } = await loadAgentPricing()

    const metric = normalizeAgentCostMetric({
        ...baseMetric,
        attributes: {
            ...baseMetric.attributes,
            token_input_text: 1_000_000,
            token_input_audio: 1_000_000,
            token_input_media: 1_000_000,
            token_output_text: 1_000_000,
            token_output_audio: 1_000_000,
            token_output_media: 1_000_000,
            token_thinking: 1_000_000,
            token_tool_use_prompt: 1_000_000,
            token_cached_input: 250_000,
        },
    })

    assert.ok(metric)
    assert.equal(metric.attributes.cost_source, 'estimated')
    assert.equal(metric.attributes.pricing_effective_from, '2026-08-23')
    assert.equal(metric.value, 31)
})

test('rejects client cost metrics without billable token attributes', async () => {
    const { normalizeAgentCostMetric } = await loadAgentPricing()

    assert.equal(normalizeAgentCostMetric(baseMetric), null)
    assert.equal(
        normalizeAgentCostMetric({
            ...baseMetric,
            attributes: { ...baseMetric.attributes, token_total: 10_000 },
        }),
        null,
    )
})

test('rejects unknown pricing models', async () => {
    const { normalizeAgentCostMetric } = await loadAgentPricing()

    assert.equal(
        normalizeAgentCostMetric({
            ...baseMetric,
            attributes: {
                ...baseMetric.attributes,
                model: 'unknown-model',
                token_input_text: 1000,
            },
        }),
        null,
    )
})
