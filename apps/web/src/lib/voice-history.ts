import { api } from '@wallet-bot/backend/api'
import type { ConvexReactClient } from 'convex/react'
import { newId } from '@/lib/new-id'

/**
 * Replication of a Live session's history to `voiceSessions` /
 * `voiceSessionEvents`, through the same V1 contract the native app uses
 * (`v1/voice/sessions:appendEvents`, see
 * `apps/native/lib/voice/voice_session_remote_sync.dart`).
 *
 * Native commits every event to Drift first and replicates from that outbox, so
 * a failed upload costs nothing. The browser has no durable local store, so the
 * outbox here is in memory: events queue, flush about a second after the last
 * write, and a failed batch is retried. Nothing in this file may throw into the
 * conversation — a broken history upload must never end a session.
 *
 * ## Deliberate differences from native
 *
 * Native also persists the raw protocol firehose (`server_message`,
 * `client_message`) and one row per PCM chunk (`audio_input_chunk`,
 * `audio_output_chunk`). Those are thousands of rows per minute, which a local
 * SQLite file absorbs and a browser round-trip does not, so web records the
 * semantic log only: lifecycle, transcript, tools and server signals. Audio
 * bytes never leave either client.
 */

/** Where the event came from, mirroring native's `direction` column. */
export type VoiceEventDirection = 'local' | 'client' | 'server'

/**
 * Native's `modality` column: which channel carried the event. Native also uses
 * `audio`, for the per-chunk rows web does not write (see above).
 */
export type VoiceEventModality = 'voice' | 'text' | 'tool'

type QueuedEvent = {
    id: string
    sequence: number
    occurredAt: bigint
    type: string
    direction: VoiceEventDirection
    modality?: VoiceEventModality
    payloadJson: string
}

/** Native uploads at most this many events per mutation. */
const BATCH_SIZE = 50

/** Debounce after the last write, matching `VoiceSessionRemoteSync.schedule`. */
const FLUSH_DELAY_MS = 1000

/** Back-off after a failed batch, also native's. */
const RETRY_DELAY_MS = 5000

export type VoiceHistoryRecorder = {
    /**
     * Bind the session to the model the token was minted for. Events recorded
     * before this point keep their sequence and upload with the first batch —
     * web only learns the model from `requestLiveToken`, while native knows it
     * up front.
     */
    open: (model: string) => void
    /** Append one event to the outbox and schedule a flush. */
    record: (
        type: string,
        direction: VoiceEventDirection,
        payload?: Record<string, unknown>,
        modality?: VoiceEventModality,
    ) => void
    /**
     * Move the session through native's lifecycle: `connecting` → `active`,
     * and `suspended` while a dropped socket waits for its auto-reconnect
     * (the reconnect marks it `active` again).
     */
    markStatus: (status: 'connecting' | 'active' | 'suspended') => void
    /**
     * Close the session. `explicit` is native's `endedExplicitly`: true when the
     * user ended it, false when the account went away underneath us (provider
     * unmount). A dropped socket is NOT an end any more — it suspends and
     * reconnects.
     */
    end: (opts: { explicit: boolean }) => void
    /** Upload everything queued. Never rejects. */
    flush: () => Promise<void>
}

/**
 * Start recording a session.
 *
 * `getOwnerId` is read at flush time, not now: it resolves from the server
 * (`v1/users/queries:getMyId`) and a session opened in the same tick as the page
 * would otherwise upload nothing. While it returns null the events stay queued
 * rather than being sent under a guessed owner.
 */
export function createVoiceHistoryRecorder(
    client: ConvexReactClient,
    getOwnerId: () => string | null,
): VoiceHistoryRecorder {
    const sessionId = newId()
    const startedAt = BigInt(Date.now())

    let model: string | null = null
    let status = 'connecting'
    let updatedAt = startedAt
    let endedAt: bigint | null = null
    let endedExplicitly = false

    let sequence = 0
    let closed = false
    let queue: QueuedEvent[] = []
    let sessionDirty = true
    let timer: ReturnType<typeof setTimeout> | null = null
    let inFlight: Promise<void> | null = null
    let trailing = false

    const touch = () => {
        // `updatedAt` is what native's `markSessionSyncedIfUnchanged` compares,
        // so it must move on every change and never go backwards.
        const now = BigInt(Date.now())
        updatedAt = now > updatedAt ? now : updatedAt + 1n
    }

    const schedule = (delay: number) => {
        if (timer !== null) clearTimeout(timer)
        timer = setTimeout(() => {
            timer = null
            void flush()
        }, delay)
    }

    const sessionPayload = (boundModel: string) => ({
        id: sessionId,
        model: boundModel,
        status,
        startedAt,
        updatedAt,
        ...(endedAt === null ? {} : { endedAt }),
        endedExplicitly,
    })

    const drain = async () => {
        // Without a model the session row would claim the wrong thing, and
        // without an owner the mutation would reject the batch anyway.
        let ownerId = getOwnerId()
        while (ownerId !== null && model !== null) {
            if (queue.length === 0 && !sessionDirty) return
            const batch = queue.slice(0, BATCH_SIZE)
            const snapshot = sessionPayload(model)
            await client.mutation(api.v1.voice.sessions.appendEvents, {
                ownerId,
                session: snapshot,
                events: batch,
            })
            queue = queue.slice(batch.length)
            // Only clear the flag if nothing changed while the batch was in
            // flight; otherwise the lifecycle update would strand here.
            if (snapshot.updatedAt === updatedAt) sessionDirty = false
            ownerId = getOwnerId()
        }
    }

    // The in-memory outbox loses its tail when the tab goes away inside the
    // debounce window (D9): flush on `pagehide` and whenever the tab is
    // hidden. Best-effort — the browser may not wait for the mutation, but
    // an attempt beats a guaranteed loss. Removed again in `end`.
    const flushOnHide = () => {
        if (document.visibilityState === 'hidden') void flush()
    }
    const flushOnPageHide = () => {
        void flush()
    }
    window.addEventListener('pagehide', flushOnPageHide)
    document.addEventListener('visibilitychange', flushOnHide)
    const removeUnloadFlush = () => {
        window.removeEventListener('pagehide', flushOnPageHide)
        document.removeEventListener('visibilitychange', flushOnHide)
    }

    const flush = async (): Promise<void> => {
        if (timer !== null) {
            clearTimeout(timer)
            timer = null
        }
        if (inFlight !== null) {
            trailing = true
            return inFlight
        }
        const run = drain()
        inFlight = run
        try {
            await run
        } catch (error) {
            // Best-effort by contract: the queue keeps the rows and the next
            // attempt re-sends them. `appendEvents` dedupes by event id.
            console.warn('voice history sync failed', error)
            schedule(RETRY_DELAY_MS)
        }
        inFlight = null
        if (trailing) {
            trailing = false
            schedule(0)
        }
    }

    return {
        open: (nextModel: string) => {
            model = nextModel
            sessionDirty = true
            touch()
            schedule(FLUSH_DELAY_MS)
        },
        record: (type, direction, payload = {}, modality) => {
            // Native's `recordClientEvent` ignores events once the session is
            // over; without this, an unmount after the socket closed would
            // append to a session already marked ended.
            if (closed) return
            sequence += 1
            const occurredAt = BigInt(Date.now())
            queue.push({
                id: newId(),
                sequence,
                occurredAt,
                type,
                direction,
                ...(modality === undefined ? {} : { modality }),
                payloadJson: JSON.stringify(payload),
            })
            touch()
            sessionDirty = true
            schedule(FLUSH_DELAY_MS)
        },
        markStatus: (next) => {
            if (status === next) return
            status = next
            sessionDirty = true
            touch()
            schedule(FLUSH_DELAY_MS)
        },
        end: ({ explicit }) => {
            if (closed) return
            closed = true
            removeUnloadFlush()
            status = 'ended'
            endedAt = BigInt(Date.now())
            endedExplicitly = explicit
            sessionDirty = true
            touch()
            void flush()
        },
        flush,
    }
}
