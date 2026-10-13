export type TranscriptRole = 'user' | 'agent'

export type TranscriptLine = {
    role: TranscriptRole
    text: string
}

/**
 * The conversation text of one stored voice-history event, or `null` when the
 * event carries none.
 *
 * Only three event types are conversation: `user_transcript_delta`,
 * `agent_transcript_delta` and `send_message` (a typed user turn). Native and
 * web both write them with a `{ text }` payload
 * (`apps/native/lib/voice/voice_event_log.dart`,
 * `apps/web/src/hooks/use-voice.ts`); everything else in a session's log (audio
 * chunks, protocol messages, lifecycle) is not conversation.
 *
 * `payloadJson` is client-written, so a malformed or unexpected payload is
 * skipped rather than allowed to fail the whole page.
 */
export function transcriptLineFromEvent(event: {
    type: string
    payloadJson: string
}): TranscriptLine | null {
    let role: TranscriptRole
    switch (event.type) {
        case 'user_transcript_delta':
        case 'send_message':
            role = 'user'
            break
        case 'agent_transcript_delta':
            role = 'agent'
            break
        default:
            return null
    }

    let payload: unknown
    try {
        payload = JSON.parse(event.payloadJson)
    } catch {
        return null
    }
    if (typeof payload !== 'object' || payload === null) return null
    if (!('text' in payload) || typeof payload.text !== 'string') return null
    if (payload.text.length === 0) return null
    return { role, text: payload.text }
}
