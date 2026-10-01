import {
    GoogleGenAI,
    type LiveConnectParameters,
    type Session,
} from '@google/genai'
import { AGENT_MODEL } from '@wallet-bot/shared'

export type LiveSession = Pick<
    Session,
    'close' | 'sendRealtimeInput' | 'sendClientContent' | 'sendToolResponse'
>

export const WEB_LIVE_VERSION = '0.5.1'
export const LEGACY_LIVE_MODEL = 'gemini-3.1-flash-live-preview'

/** SDK owns the wire protocol; we only gate readiness and cancellation. */
export async function connectGeminiLive(opts: {
    token: string
    model: string
    signal: AbortSignal
    callbacks: LiveConnectParameters['callbacks']
    connect?: (params: LiveConnectParameters) => Promise<LiveSession>
    timeoutMs?: number
}): Promise<LiveSession> {
    if (opts.model !== AGENT_MODEL && opts.model !== LEGACY_LIVE_MODEL) {
        throw new Error(`Unsupported Live model: ${opts.model}`)
    }
    opts.signal.throwIfAborted()
    let session: LiveSession | undefined
    let abandoned = false
    let accept!: () => void
    let reject!: (error: unknown) => void
    const setup = new Promise<void>((resolve) => {
        accept = resolve
    })
    const failure = new Promise<never>((_, fail) => {
        reject = fail
    })
    void failure.catch(() => {})
    const abort = () =>
        reject(opts.signal.reason ?? new Error('Connection cancelled'))
    opts.signal.addEventListener('abort', abort, { once: true })
    const timer = setTimeout(
        () => reject(new Error('Gemini setup timed out')),
        opts.timeoutMs ?? 20000,
    )
    const connect =
        opts.connect ??
        ((params) =>
            new GoogleGenAI({
                apiKey: opts.token,
                httpOptions: { apiVersion: 'v1alpha' },
            }).live.connect(params))
    try {
        const opening = connect({
            model: opts.model,
            callbacks: {
                ...opts.callbacks,
                onmessage: (message) => {
                    if (abandoned || opts.signal.aborted) return
                    if (message.setupComplete) accept()
                    opts.callbacks.onmessage?.(message)
                },
                onerror: (event) => {
                    reject(new Error(event.message || 'Gemini socket error'))
                    if (!abandoned && !opts.signal.aborted)
                        opts.callbacks.onerror?.(event)
                },
                onclose: (event) => {
                    reject(
                        new Error(`Gemini closed before setup (${event.code})`),
                    )
                    if (!abandoned && !opts.signal.aborted)
                        opts.callbacks.onclose?.(event)
                },
            },
        }).then((value) => {
            session = value
            if (abandoned || opts.signal.aborted) value.close()
            return value
        })
        // The installed SDK resolves after sending setup, before setupComplete.
        // Race cancellation/timeout against socket opening as well as setup.
        const ready = Promise.all([opening, setup]).then(([value]) => value)
        return await Promise.race([ready, failure])
    } catch (error) {
        abandoned = true
        session?.close()
        throw error
    } finally {
        clearTimeout(timer)
        opts.signal.removeEventListener('abort', abort)
    }
}
