// Mirrors apps/native/test/voice/conversation_seed_test.dart case for case,
// so the two seed builders can never quietly diverge.

import { describe, expect, it } from 'vitest'
import {
    buildConversationSeed,
    type ConversationEvent,
    parseGoogleDuration,
} from './voice-seed'

describe('buildConversationSeed', () => {
    it('builds User/Assistant transcript from deltas and turn boundaries', () => {
        const seed = buildConversationSeed([
            { type: 'user_transcript_delta', text: '¿Qué eventos ' },
            { type: 'user_transcript_delta', text: 'tengo esta semana?' },
            { type: 'agent_transcript_delta', text: 'Esta semana tuviste ' },
            {
                type: 'agent_transcript_delta',
                text: 'un gasto de veinticinco mil pesos.',
            },
            { type: 'agent_turn_complete' },
            {
                type: 'user_transcript_delta',
                text: 'Y gasté 10 000 pesos en pizza.',
            },
            {
                type: 'agent_transcript_delta',
                text: 'De acuerdo. ¿Con qué cuenta pagaste?',
            },
            { type: 'agent_interrupted' },
        ])

        expect(seed).not.toBeNull()
        const body = seed as string
        const order = [
            'User: ¿Qué eventos tengo esta semana?',
            'Assistant: Esta semana tuviste un gasto de veinticinco mil pesos.',
            'User: Y gasté 10 000 pesos en pizza.',
            'Assistant: De acuerdo. ¿Con qué cuenta pagaste?',
        ]
        let cursor = -1
        for (const line of order) {
            const index = body.indexOf(line)
            expect(index, line).toBeGreaterThan(cursor)
            cursor = index
        }
        expect(body).toContain('Do not greet again')
    })

    it('typed messages appear as user lines', () => {
        const seed = buildConversationSeed([
            { type: 'send_message', text: 'hola' },
            { type: 'agent_transcript_delta', text: '¡Hola!' },
            { type: 'agent_turn_complete' },
        ])
        expect(seed).toContain('User: hola')
        expect(seed).toContain('Assistant: ¡Hola!')
    })

    it('non-conversation events are ignored', () => {
        const seed = buildConversationSeed([
            { type: 'tool_call' },
            { type: 'tool_result' },
            { type: 'tool_cancelled' },
        ])
        expect(seed).toBeNull()
    })

    it('trailing pending texts are excluded, delivered ones kept', () => {
        const seed = buildConversationSeed(
            [
                { type: 'send_message', text: 'hola' },
                {
                    type: 'agent_transcript_delta',
                    text: '¡Hola! ¿En qué te ayudo?',
                },
                { type: 'agent_turn_complete' },
                { type: 'send_message', text: 'kek' },
                { type: 'send_message', text: 'hey' },
            ],
            { pendingTexts: ['kek', 'hey'] },
        )

        expect(seed).toContain('User: hola')
        expect(seed).not.toContain('kek')
        expect(seed).not.toContain('hey')
    })

    it('a delivered duplicate of a pending text is not over-trimmed', () => {
        const seed = buildConversationSeed(
            [
                { type: 'send_message', text: 'hola' },
                { type: 'agent_transcript_delta', text: '¡Hola!' },
                { type: 'agent_turn_complete' },
                { type: 'send_message', text: 'hola' },
            ],
            { pendingTexts: ['hola'] },
        )

        // Only the trailing queued copy is trimmed; the answered one stays.
        expect(seed).toContain('User: hola')
        expect(seed).toContain('Assistant: ¡Hola!')
    })

    it('returns null when there is nothing to restore', () => {
        expect(buildConversationSeed([])).toBeNull()
        expect(
            buildConversationSeed([{ type: 'send_message', text: 'x' }], {
                pendingTexts: ['x'],
            }),
        ).toBeNull()
    })

    it('long transcripts are truncated from the front', () => {
        const events: ConversationEvent[] = []
        for (let i = 0; i < 200; i++) {
            events.push({
                type: 'user_transcript_delta',
                text: `Mensaje número ${i} con contenido largo.`,
            })
            events.push({
                type: 'agent_transcript_delta',
                text: `Respuesta número ${i} con contenido largo.`,
            })
            events.push({ type: 'agent_turn_complete' })
        }
        const seed = buildConversationSeed(events, { maxChars: 2000 })
        expect(seed).not.toBeNull()
        const body = seed as string

        expect(body.length).toBeLessThan(2600)
        expect(body).toContain('recent part of the conversation')
        expect(body).toContain('Respuesta número 199')
        expect(body).not.toContain('Mensaje número 0 ')
    })
})

describe('parseGoogleDuration', () => {
    it('parses whole and fractional second strings', () => {
        expect(parseGoogleDuration('5s')).toBe(5000)
        expect(parseGoogleDuration('2.5s')).toBe(2500)
    })

    it('rejects anything else', () => {
        expect(parseGoogleDuration(undefined)).toBeNull()
        expect(parseGoogleDuration('')).toBeNull()
        expect(parseGoogleDuration('5m')).toBeNull()
        expect(parseGoogleDuration('abc')).toBeNull()
    })
})
