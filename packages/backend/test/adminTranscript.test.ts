import { describe, expect, it } from 'vitest'
import { transcriptLineFromEvent } from '../convex/admin/utils'

describe('transcriptLineFromEvent', () => {
    it('reads user and agent deltas and typed messages', () => {
        expect(
            transcriptLineFromEvent({
                type: 'user_transcript_delta',
                payloadJson: '{"text":"hola"}',
            }),
        ).toEqual({ role: 'user', text: 'hola' })
        expect(
            transcriptLineFromEvent({
                type: 'agent_transcript_delta',
                payloadJson: '{"text":"listo"}',
            }),
        ).toEqual({ role: 'agent', text: 'listo' })
        expect(
            transcriptLineFromEvent({
                type: 'send_message',
                payloadJson: '{"interactionModality":"text","text":"gasté 5"}',
            }),
        ).toEqual({ role: 'user', text: 'gasté 5' })
    })

    it('skips events that are not conversation', () => {
        expect(
            transcriptLineFromEvent({
                type: 'audio_input_chunk',
                payloadJson: '{"text":"nope"}',
            }),
        ).toBeNull()
    })

    it('skips malformed, empty or non-text payloads instead of throwing', () => {
        const payloads = ['not json', '{}', '{"text":""}', '{"text":1}', 'null']
        for (const payloadJson of payloads) {
            expect(
                transcriptLineFromEvent({
                    type: 'user_transcript_delta',
                    payloadJson,
                }),
            ).toBeNull()
        }
    })
})
