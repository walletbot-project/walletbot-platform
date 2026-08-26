// TS mirror of native's conversation-seed builder
// (apps/native/lib/voice/voice_event.dart — `buildConversationSeed` and
// `kConversationEventTypes`). Same folding rules, same 6000-char
// front-truncation, same pending-text de-duplication, so a reconnect restores
// the model's context identically on both platforms.
//
// Gemini session-resumption handles are not reliable for this: after an
// abrupt disconnect a handle stops resuming within seconds, and the server
// then silently opens a BLANK session instead of failing (verified against
// the live API, 2026-08-21). Re-seeding from the local log is deterministic
// and guarantees the model's context always matches the conversation the
// user sees on screen.

/**
 * The in-memory conversation event log a session accumulates — the substrate
 * for the reconnect seed. Mirrors the subset of native's durable log that
 * carries conversation content (`kConversationEventTypes`); everything else
 * (audio chunks, lifecycle noise) never enters this log.
 */
export type ConversationEvent =
    | { type: 'user_transcript_delta'; text: string }
    | { type: 'agent_transcript_delta'; text: string }
    | { type: 'agent_turn_complete' }
    | { type: 'agent_interrupted' }
    | { type: 'send_message'; text: string }
    | { type: 'tool_call' }
    | { type: 'tool_result' }
    | { type: 'tool_cancelled' }

const DEFAULT_MAX_CHARS = 6000

/**
 * Builds the transcript seed a (re)connect sends to the model as its first
 * client message, restoring conversation context from the session's event
 * log.
 *
 * `pendingTexts` are typed messages still queued for live delivery after the
 * seed — their trailing `send_message` entries are excluded so the model
 * doesn't see them twice. Returns null when there is nothing to restore.
 */
export function buildConversationSeed(
    events: readonly ConversationEvent[],
    opts: { pendingTexts?: readonly string[]; maxChars?: number } = {},
): string | null {
    const maxChars = opts.maxChars ?? DEFAULT_MAX_CHARS
    const lines: { role: 'User' | 'Assistant'; text: string }[] = []
    let user = ''
    let agent = ''

    const flushUser = () => {
        const text = user.trim()
        if (text) lines.push({ role: 'User', text })
        user = ''
    }
    const flushAgent = () => {
        const text = agent.trim()
        if (text) lines.push({ role: 'Assistant', text })
        agent = ''
    }

    for (const event of events) {
        switch (event.type) {
            case 'user_transcript_delta':
                flushAgent()
                user += event.text
                break
            case 'agent_transcript_delta':
                flushUser()
                agent += event.text
                break
            case 'agent_turn_complete':
            case 'agent_interrupted':
                flushAgent()
                break
            case 'send_message':
                if (event.text) {
                    flushUser()
                    flushAgent()
                    lines.push({ role: 'User', text: event.text })
                }
                break
            default:
                break
        }
    }
    flushUser()
    flushAgent()

    // Trailing user messages that are still queued for live delivery would
    // otherwise appear twice: once in the seed, once when the queue flushes.
    const pending = [...(opts.pendingTexts ?? [])]
    while (lines.length > 0 && pending.length > 0) {
        const last = lines[lines.length - 1]
        if (last.role !== 'User') break
        const index = pending.indexOf(last.text)
        if (index < 0) break
        pending.splice(index, 1)
        lines.pop()
    }

    if (lines.length === 0) return null

    let transcript = lines
        .map((line) => `${line.role}: ${line.text}`)
        .join('\n')
    let truncated = false
    if (transcript.length > maxChars) {
        transcript = transcript.slice(transcript.length - maxChars)
        truncated = true
    }
    const scope = truncated
        ? 'the recent part of the conversation'
        : 'the conversation'
    return (
        `[Context restore: the previous connection dropped. This is ` +
        `${scope} so far:]\n${transcript}\n` +
        `[End of transcript. Continue this conversation naturally in the same ` +
        `language. Do not greet again and do not mention the reconnection.]`
    )
}

/**
 * Parses Google's protobuf Duration wire string ("5s", "2.5s") — the shape
 * `goAway.timeLeft` arrives in. Null for anything else.
 */
export function parseGoogleDuration(value: string | undefined): number | null {
    if (!value) return null
    const match = /^([0-9]+(?:\.[0-9]+)?)s$/.exec(value)
    if (!match) return null
    const seconds = Number.parseFloat(match[1])
    if (!Number.isFinite(seconds)) return null
    return Math.round(seconds * 1000)
}
