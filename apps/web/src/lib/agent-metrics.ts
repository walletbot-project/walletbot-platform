import { authClient } from '@/lib/auth-client'
import { WEB_LIVE_VERSION } from '@/lib/gemini-live'
import { clientDurationBucket, createTelemetryClient } from '@/lib/telemetry'

/**
 * Client-observed voice agent latency — the web half of native's
 * `AgentMetrics.recordSetupCompleteBucket` / `recordFirstResponse`
 * (`apps/native/lib/telemetry/agent_metrics.dart`). Cost metrics are not
 * here: web voice cost already reaches the backend through
 * `v1/voice/sessions.ts:appendEvents`.
 */

// One client per page load, so `sessionId` is per page load as well.
const telemetry = createTelemetryClient({
    siteUrl: import.meta.env.VITE_CONVEX_SITE_URL,
    // The version web already reports to the backend at token mint
    // (`use-voice.ts`) and in agent reports (`agent-context.ts`).
    appVersion: WEB_LIVE_VERSION,
    // The same Convex JWT `ConvexBetterAuthProvider` hands the Convex client.
    // Signed out (or the fetch failed) → null, and the metric goes anonymous.
    getAccessToken: async () => {
        const { data } = await authClient.convex.token({
            fetchOptions: { throw: false },
        })
        return data?.token ?? null
    },
})

/**
 * Time from the start of a connection attempt to the Live session being ready
 * (`setupComplete` received and the previous socket's tools settled).
 * `resumed` is native's meaning: the attempt followed a failed one.
 */
export function recordSetupComplete({
    elapsedMs,
    resumed,
}: {
    elapsedMs: number
    resumed: boolean
}): void {
    telemetry.trackMetric({
        name: 'voice.connect.setup_complete_bucket_count',
        type: 'counter',
        value: 1,
        unit: 'count',
        attributes: {
            bucket: clientDurationBucket(elapsedMs),
            platform: 'web',
            resumed,
        },
    })
}

/**
 * Time from the user's turn being sent (voice: audio stream end; text: the
 * typed turn) to the model's first transcript delta or audio chunk. The
 * backend derives `agent.response.first_token_bucket_count` from this.
 */
export function recordFirstResponse({
    elapsedMs,
    mode,
}: {
    elapsedMs: number
    mode: 'text' | 'voice'
}): void {
    telemetry.trackMetric({
        name: 'agent.response.first_token_ms',
        type: 'gauge',
        value: Math.round(elapsedMs),
        unit: 'ms',
        attributes: { mode, platform: 'web' },
    })
}
