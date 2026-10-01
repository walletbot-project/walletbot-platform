import type { MetricInput } from '../../telemetry/types'

const count = (value: unknown): number =>
    typeof value === 'number' && Number.isFinite(value) && value > 0
        ? Math.floor(value)
        : 0

/** Convert each generation's usage directly; never subtract the prior turn. */
export function webVoiceMetric(args: {
    userId: string
    sessionId: string
    event: { id: string; type: string; occurredAt: bigint; payloadJson: string }
}): MetricInput | null {
    let payload: Record<string, unknown>
    try {
        payload = JSON.parse(args.event.payloadJson)
    } catch {
        return null
    }
    if (!payload || typeof payload !== 'object') return null
    const model = payload.model
    if (
        model !== 'gemini-3.8-live' &&
        model !== 'gemini-3.1-flash-live-preview'
    )
        return null
    const mode =
        payload.mode === 'audio'
            ? 'voice'
            : payload.mode === 'text'
              ? 'text'
              : 'mixed'
    const common = {
        userId: args.userId,
        sessionId: args.sessionId,
        sampleId: args.event.id,
        timestamp: Number(args.event.occurredAt),
        source: 'web' as const,
        platform: 'web' as const,
    }
    if (args.event.type === 'agent_turn_complete') {
        return {
            ...common,
            name: 'agent.interactions.completed_count',
            type: 'counter',
            value: 1,
            unit: 'count',
            attributes: { model, mode, interaction_type: mode },
        }
    }
    if (args.event.type !== 'usage_metadata') return null
    const tokens: Record<string, number> = {}
    const add = (key: string, value: unknown) => {
        const n = count(value)
        if (n) tokens[key] = (tokens[key] ?? 0) + n
    }
    for (const [direction, total, details] of [
        ['input', payload.promptTokenCount, payload.promptTokensDetails],
        ['output', payload.responseTokenCount, payload.responseTokensDetails],
    ] as const) {
        let detailed = 0
        if (Array.isArray(details)) {
            for (const entry of details) {
                if (!entry || typeof entry !== 'object') continue
                const n = count(entry.tokenCount)
                const modality = String(entry.modality).toLowerCase()
                const suffix =
                    modality === 'audio'
                        ? 'audio'
                        : ['video', 'image'].includes(modality)
                          ? 'media'
                          : 'text'
                add(`token_${direction}_${suffix}`, n)
                detailed += n
            }
        }
        add(`token_${direction}_text`, Math.max(0, count(total) - detailed))
    }
    add('token_thinking', payload.thoughtsTokenCount)
    add('token_cached_input', payload.cachedContentTokenCount)
    add('token_tool_use_prompt', payload.toolUsePromptTokenCount)
    add('token_total', payload.totalTokenCount)
    return {
        ...common,
        name: 'agent.interaction.cost_usd',
        type: 'gauge',
        value: 0,
        unit: 'usd',
        attributes: { model, mode, cost_source: 'estimated', ...tokens },
    }
}
