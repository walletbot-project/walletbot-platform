import type { MetricAttributeValue, MetricInput } from './types'

type AgentCostMetricName = 'agent.session.cost_usd' | 'agent.interaction.cost_usd'

type AgentPrice = {
    model: string
    effectiveFrom: number
    inputTextUsdPerMillion: number
    inputAudioUsdPerMillion: number
    inputMediaUsdPerMillion: number
    outputTextUsdPerMillion: number
    outputAudioUsdPerMillion: number
    outputMediaUsdPerMillion: number
    cachedInputUsdPerMillion?: number
}

const pricingCatalog: AgentPrice[] = [
    {
        model: 'gemini-3.1-flash-live-preview',
        effectiveFrom: Date.parse('2026-08-23T00:00:00.000Z'),
        inputTextUsdPerMillion: 0.75,
        inputAudioUsdPerMillion: 3.0,
        inputMediaUsdPerMillion: 1.0,
        outputTextUsdPerMillion: 4.5,
        outputAudioUsdPerMillion: 12.0,
        outputMediaUsdPerMillion: 4.5,
        // The current public Live pricing table does not list a separate
        // context-cache rate for this model, so cached tokens remain estimated
        // at regular text input price until billing reconciliation is wired.
        cachedInputUsdPerMillion: 0.75,
    },
]

const tokenAttributeKeys = [
    'token_input_text',
    'token_input_audio',
    'token_input_media',
    'token_output_text',
    'token_output_audio',
    'token_output_media',
    'token_thinking',
    'token_tool_use_prompt',
    'token_cached_input',
] as const

export const agentPricingAttributeSpec = {
    token_input_text: 'string',
    token_input_audio: 'string',
    token_input_media: 'string',
    token_output_text: 'string',
    token_output_audio: 'string',
    token_output_media: 'string',
    token_thinking: 'string',
    token_tool_use_prompt: 'string',
    token_cached_input: 'string',
    token_total: 'string',
    pricing_effective_from: 'string',
} satisfies Record<string, 'string'>

const numberAttribute = (
    attributes: Record<string, MetricAttributeValue> | undefined,
    key: string,
): number => {
    const value = attributes?.[key]
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
        return 0
    }
    return value
}

const stringAttribute = (
    attributes: Record<string, MetricAttributeValue> | undefined,
    key: string,
): string | undefined => {
    const value = attributes?.[key]
    return typeof value === 'string' && value.length > 0 ? value : undefined
}

const tokensToUsd = (tokens: number, usdPerMillion: number): number =>
    (tokens * usdPerMillion) / 1_000_000

const priceFor = (model: string, timestamp: number): AgentPrice | undefined => {
    const candidates = pricingCatalog
        .filter(
            (price) =>
                price.model === model && price.effectiveFrom <= timestamp,
        )
        .sort((a, b) => b.effectiveFrom - a.effectiveFrom)
    return candidates[0]
}

const hasTokenAttributes = (
    attributes: Record<string, MetricAttributeValue> | undefined,
): boolean =>
    tokenAttributeKeys.some(
        (key) => numberAttribute(attributes, key) > 0,
    )

export const isAgentCostMetric = (
    name: string,
): name is AgentCostMetricName =>
    name === 'agent.session.cost_usd' || name === 'agent.interaction.cost_usd'

export const costBucket = (costUsd: number): string => {
    if (costUsd < 0.01) return '0-0.01'
    if (costUsd < 0.05) return '0.01-0.05'
    if (costUsd < 0.1) return '0.05-0.10'
    if (costUsd < 0.5) return '0.10-0.50'
    if (costUsd < 1) return '0.50-1.00'
    return '1.00+'
}

export const normalizeAgentCostMetric = (
    metric: MetricInput,
): MetricInput | null => {
    if (!isAgentCostMetric(metric.name)) return metric

    if (!hasTokenAttributes(metric.attributes)) return null

    const model = stringAttribute(metric.attributes, 'model') ?? 'unknown'
    const price = priceFor(model, metric.timestamp)
    if (!price) return null

    const cachedInput = numberAttribute(
        metric.attributes,
        'token_cached_input',
    )
    const inputText = Math.max(
        0,
        numberAttribute(metric.attributes, 'token_input_text') - cachedInput,
    )
    const costUsd =
        tokensToUsd(inputText, price.inputTextUsdPerMillion) +
        tokensToUsd(
            numberAttribute(metric.attributes, 'token_input_audio'),
            price.inputAudioUsdPerMillion,
        ) +
        tokensToUsd(
            numberAttribute(metric.attributes, 'token_input_media'),
            price.inputMediaUsdPerMillion,
        ) +
        tokensToUsd(
            numberAttribute(metric.attributes, 'token_output_text'),
            price.outputTextUsdPerMillion,
        ) +
        tokensToUsd(
            numberAttribute(metric.attributes, 'token_output_audio'),
            price.outputAudioUsdPerMillion,
        ) +
        tokensToUsd(
            numberAttribute(metric.attributes, 'token_output_media'),
            price.outputMediaUsdPerMillion,
        ) +
        tokensToUsd(
            numberAttribute(metric.attributes, 'token_thinking'),
            price.outputTextUsdPerMillion,
        ) +
        tokensToUsd(
            numberAttribute(metric.attributes, 'token_tool_use_prompt'),
            price.inputTextUsdPerMillion,
        ) +
        tokensToUsd(cachedInput, price.cachedInputUsdPerMillion ?? 0)

    if (!Number.isFinite(costUsd) || costUsd <= 0) return null

    return {
        ...metric,
        value: costUsd,
        attributes: {
            ...metric.attributes,
            cost_source: 'estimated',
            pricing_effective_from: new Date(price.effectiveFrom)
                .toISOString()
                .slice(0, 10),
        },
    }
}
