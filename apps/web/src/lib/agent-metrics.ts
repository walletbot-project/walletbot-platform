import type { UsageMetadata } from '@google/genai'
import type { ConvexReactClient } from 'convex/react'
import { newId } from '@/lib/new-id'
import { recordWebMetricBatch, type TelemetryMetric } from '@/lib/telemetry'

type SessionMode = 'voice' | 'text' | 'mixed'
type InteractionType = SessionMode | 'tool'

// Local estimate used only to detect cumulative usage changes. The backend
// recalculates accepted costs from token attributes and its pricing catalog.
const gemini31FlashLiveInputTextUsdPerMillion = 0.75
const gemini31FlashLiveInputAudioUsdPerMillion = 3.0
const gemini31FlashLiveInputMediaUsdPerMillion = 1.0
const gemini31FlashLiveOutputTextUsdPerMillion = 4.5
const gemini31FlashLiveOutputAudioUsdPerMillion = 12.0

export type AgentInteractionCostSample = {
    sampleId: string
    interactionType: InteractionType
    costUsd: number
    tokenAttributes: Record<string, number>
}

export class AgentInteractionCostTracker {
    private lastTotalCostUsd: number | null = null
    private lastTokenAttributes: Record<string, number> | null = null
    private toolCallSinceLastUsage = false
    private readonly nextId: () => string

    constructor(nextId: () => string = newId) {
        this.nextId = nextId
    }

    markToolCall(): void {
        this.toolCallSinceLastUsage = true
    }

    nextSample({
        sessionId,
        totalCostUsd,
        fallbackInteractionType,
        tokenAttributes,
    }: {
        sessionId: string
        totalCostUsd: number
        fallbackInteractionType: SessionMode
        tokenAttributes: Record<string, number>
    }): AgentInteractionCostSample | null {
        const interactionType = this.toolCallSinceLastUsage
            ? 'tool'
            : fallbackInteractionType
        this.toolCallSinceLastUsage = false

        const previousTotalCostUsd = this.lastTotalCostUsd
        if (totalCostUsd === previousTotalCostUsd) return null

        const previousTokenAttributes = this.lastTokenAttributes
        const interactionCostUsd =
            previousTotalCostUsd === null || totalCostUsd < previousTotalCostUsd
                ? totalCostUsd
                : totalCostUsd - previousTotalCostUsd
        this.lastTotalCostUsd = totalCostUsd
        this.lastTokenAttributes = tokenAttributes
        if (interactionCostUsd <= 0) return null

        return {
            sampleId: `${sessionId}:${this.nextId()}`,
            interactionType,
            costUsd: interactionCostUsd,
            tokenAttributes: deltaTokenAttributes(
                tokenAttributes,
                previousTokenAttributes,
            ),
        }
    }
}

export const usageTokenAttributes = (
    usage: UsageMetadata,
): Record<string, number> => {
    const promptTokens = intValue(usage.promptTokenCount)
    const responseTokens = intValue(usage.responseTokenCount)
    const totalTokens = intValue(usage.totalTokenCount)

    const promptDetails = tokenDetails(usage.promptTokensDetails)
    const responseDetails = tokenDetails(usage.responseTokensDetails)

    const attributes: Record<string, number> = {}
    addTokenDetails(attributes, {
        prefix: 'token_input',
        totalTokens: promptTokens,
        details: promptDetails,
    })
    addTokenDetails(attributes, {
        prefix: 'token_output',
        totalTokens: responseTokens,
        details: responseDetails,
    })
    addPositive(
        attributes,
        'token_thinking',
        intValue(usage.thoughtsTokenCount),
    )
    addPositive(
        attributes,
        'token_tool_use_prompt',
        intValue(usage.toolUsePromptTokenCount),
    )
    addPositive(
        attributes,
        'token_cached_input',
        intValue(usage.cachedContentTokenCount),
    )
    addPositive(attributes, 'token_total', totalTokens)
    return attributes
}

export const estimateSessionCostUsd = (usage: UsageMetadata): number | null => {
    const promptTokens = intValue(usage.promptTokenCount)
    const responseTokens = intValue(usage.responseTokenCount)
    const totalTokens = intValue(usage.totalTokenCount)

    const promptDetails = tokenDetails(usage.promptTokensDetails)
    const responseDetails = tokenDetails(usage.responseTokensDetails)

    const estimatedInputUsd = estimateCost({
        totalTokens: promptTokens,
        details: promptDetails,
        textUsdPerMillion: gemini31FlashLiveInputTextUsdPerMillion,
        audioUsdPerMillion: gemini31FlashLiveInputAudioUsdPerMillion,
        mediaUsdPerMillion: gemini31FlashLiveInputMediaUsdPerMillion,
    })
    const estimatedOutputUsd = estimateCost({
        totalTokens: responseTokens,
        details: responseDetails,
        textUsdPerMillion: gemini31FlashLiveOutputTextUsdPerMillion,
        audioUsdPerMillion: gemini31FlashLiveOutputAudioUsdPerMillion,
        mediaUsdPerMillion: gemini31FlashLiveOutputTextUsdPerMillion,
    })

    if (estimatedInputUsd === null && estimatedOutputUsd === null) {
        if (totalTokens === null) return null
        return tokensToUsd(
            totalTokens,
            gemini31FlashLiveOutputTextUsdPerMillion,
        )
    }
    return (estimatedInputUsd ?? 0) + (estimatedOutputUsd ?? 0)
}

export const recordAgentSessionStarted = (
    client: ConvexReactClient,
    args: {
        sessionId: string
        model: string
        resumed: boolean
    },
): Promise<void> =>
    recordWebMetricBatch(client, [
        {
            name: 'agent.sessions.started_count',
            timestamp: Date.now(),
            type: 'counter',
            value: 1,
            unit: 'count',
            attributes: {
                model: args.model,
                start_kind: args.resumed ? 'resumed' : 'new',
            },
            sessionId: args.sessionId,
        },
    ])

export const recordAgentSessionCostFromUsage = (
    client: ConvexReactClient,
    args: {
        sessionId: string
        model: string
        mode: SessionMode
        usage: UsageMetadata
    },
): Promise<void> => {
    const costUsd = estimateSessionCostUsd(args.usage)
    if (costUsd === null) return Promise.resolve()

    return recordWebMetricBatch(client, [
        costGaugeMetric({
            name: 'agent.session.cost_usd',
            sessionId: args.sessionId,
            model: args.model,
            mode: args.mode,
            costUsd,
            tokenAttributes: usageTokenAttributes(args.usage),
        }),
    ])
}

export const recordAgentInteractionCost = (
    client: ConvexReactClient,
    args: {
        sessionId: string
        sampleId: string
        model: string
        mode: SessionMode
        interactionType: InteractionType
        costUsd: number
        tokenAttributes: Record<string, number>
    },
): Promise<void> =>
    recordWebMetricBatch(client, [
        costGaugeMetric({
            name: 'agent.interaction.cost_usd',
            sessionId: args.sessionId,
            sampleId: args.sampleId,
            model: args.model,
            mode: args.mode,
            costUsd: args.costUsd,
            tokenAttributes: args.tokenAttributes,
        }),
        {
            name: 'agent.interactions.completed_count',
            timestamp: Date.now(),
            type: 'counter',
            value: 1,
            unit: 'count',
            attributes: {
                model: args.model,
                mode: args.mode,
                interaction_type: args.interactionType,
            },
            sessionId: args.sessionId,
        },
    ])

const costGaugeMetric = ({
    name,
    sessionId,
    sampleId,
    model,
    mode,
    costUsd,
    tokenAttributes,
}: {
    name: 'agent.session.cost_usd' | 'agent.interaction.cost_usd'
    sessionId: string
    sampleId?: string
    model: string
    mode: SessionMode
    costUsd: number
    tokenAttributes: Record<string, number>
}): TelemetryMetric => ({
    name,
    timestamp: Date.now(),
    type: 'gauge',
    value: costUsd,
    unit: 'usd',
    attributes: {
        model,
        mode,
        cost_source: 'estimated',
        ...tokenAttributes,
    },
    sessionId,
    sampleId,
})

const estimateCost = ({
    totalTokens,
    details,
    textUsdPerMillion,
    audioUsdPerMillion,
    mediaUsdPerMillion,
}: {
    totalTokens: number | null
    details: Record<string, number> | null
    textUsdPerMillion: number
    audioUsdPerMillion: number
    mediaUsdPerMillion: number
}): number | null => {
    if (details === null || Object.keys(details).length === 0) {
        if (totalTokens === null) return null
        return tokensToUsd(totalTokens, textUsdPerMillion)
    }

    let cost = 0
    let detailedTokens = 0
    for (const [modality, tokens] of Object.entries(details)) {
        detailedTokens += tokens
        const price =
            modality === 'audio'
                ? audioUsdPerMillion
                : modality === 'image' || modality === 'video'
                  ? mediaUsdPerMillion
                  : textUsdPerMillion
        cost += tokensToUsd(tokens, price)
    }

    const remainder = totalTokens === null ? 0 : totalTokens - detailedTokens
    if (remainder > 0) cost += tokensToUsd(remainder, textUsdPerMillion)
    return cost
}

const tokensToUsd = (tokens: number, usdPerMillion: number): number =>
    (tokens * usdPerMillion) / 1_000_000

const tokenDetails = (value: unknown): Record<string, number> | null => {
    if (!Array.isArray(value)) return null
    const details: Record<string, number> = {}
    for (const item of value) {
        if (!isRecord(item)) continue
        const rawModality =
            valueAsString(item.modality) ??
            valueAsString(item.modalityType) ??
            'text'
        const tokens = intValue(item.tokenCount)
        if (tokens === null) continue
        const modality = rawModality.toLowerCase()
        details[modality] = (details[modality] ?? 0) + tokens
    }
    return details
}

const intValue = (value: unknown): number | null => {
    if (typeof value === 'number' && Number.isFinite(value)) {
        return Math.round(value)
    }
    if (typeof value === 'string' && /^[+-]?\d+$/.test(value)) {
        const parsed = Number(value)
        return Number.isFinite(parsed) ? parsed : null
    }
    return null
}

const valueAsString = (value: unknown): string | null =>
    value === null || value === undefined ? null : String(value)

const isRecord = (value: unknown): value is Record<string, unknown> =>
    typeof value === 'object' && value !== null && !Array.isArray(value)

const addTokenDetails = (
    attributes: Record<string, number>,
    {
        prefix,
        totalTokens,
        details,
    }: {
        prefix: string
        totalTokens: number | null
        details: Record<string, number> | null
    },
): void => {
    if (details === null || Object.keys(details).length === 0) {
        addPositive(attributes, `${prefix}_text`, totalTokens)
        return
    }

    let detailedTokens = 0
    for (const [modality, tokens] of Object.entries(details)) {
        detailedTokens += tokens
        const suffix =
            modality === 'audio'
                ? 'audio'
                : modality === 'image' || modality === 'video'
                  ? 'media'
                  : 'text'
        attributes[`${prefix}_${suffix}`] =
            (attributes[`${prefix}_${suffix}`] ?? 0) + tokens
    }

    const remainder = totalTokens === null ? 0 : totalTokens - detailedTokens
    addPositive(attributes, `${prefix}_text`, remainder)
}

const addPositive = (
    attributes: Record<string, number>,
    key: string,
    value: number | null,
): void => {
    if (value === null || value <= 0) return
    attributes[key] = (attributes[key] ?? 0) + value
}

const deltaTokenAttributes = (
    current: Record<string, number>,
    previous: Record<string, number> | null,
): Record<string, number> => {
    if (previous === null) return current
    const delta: Record<string, number> = {}
    for (const [key, currentValue] of Object.entries(current)) {
        const value = currentValue - (previous[key] ?? 0)
        if (value > 0) delta[key] = value
    }
    return delta
}
