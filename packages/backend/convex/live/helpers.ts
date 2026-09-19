import { MAX_DEVICE_ID_LENGTH } from '@wallet-bot/shared'

/**
 * Who is asking for a live token: a signed-in user, or an unauthenticated
 * native device (a local account).
 *
 * The identity always wins when one is present, so a remote account can never
 * be billed against (or hide behind) a device id it also sends.
 */
export type LiveSubmitter =
    | { kind: 'user'; userId: string }
    | { kind: 'device'; deviceId: string }

/** Why a mint was refused. Mirrored in both clients' copy. */
export type LiveTokenError =
    | 'rate_limited'
    | 'unidentified_client'
    | 'local_accounts_disabled'
    /** iOS only: the AI disclosure has not been consented to yet. */
    | 'ai_consent_required'

export type LiveMintGate =
    | { ok: true }
    | { ok: false; error: LiveTokenError; retryAfter?: number }

/**
 * Wire shape of a mint response, shared by the Convex action and the HTTP
 * route. Written out rather than inferred because the action calls an internal
 * mutation, and inferring through the generated api would make its own type
 * circular.
 *
 * `timings` is loose on purpose: each entry point reports its own breakdown
 * (`actionMs` vs `authMs`/`httpTotalMs`) on top of the mint's own numbers, and
 * the clients only ever log them.
 */
export type LiveTokenResponse =
    | {
          token: string
          expireTime: string
          model: string
          timings: Record<string, number>
      }
    | { error: LiveTokenError; retryAfter?: number }

/**
 * Pure so the two entry points can resolve identity their own way — the Convex
 * action from `ctx.auth`, the HTTP route from a validated Bearer session — and
 * still agree on precedence and on what counts as a usable device id.
 */
export function resolveLiveSubmitter(
    userId: string | null,
    deviceId: string | undefined,
): LiveSubmitter | null {
    if (userId) return { kind: 'user', userId }

    const trimmed = deviceId?.trim()
    if (!trimmed || trimmed.length > MAX_DEVICE_ID_LENGTH) return null
    return { kind: 'device', deviceId: trimmed }
}
