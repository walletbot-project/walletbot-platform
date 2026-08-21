/**
 * The web app's counterpart to native's `ClientInfo`
 * (`apps/native/lib/app_config/client_info.dart`) — who this client claims to
 * be when it reports something to the backend.
 *
 * Everything here is a *claim*. The backend stores it for triage and never
 * authorizes on it (CLAUDE.md: the client is not trustable).
 */

export const WEB_PLATFORM = 'web'

/**
 * The web app is unversioned: `apps/web/package.json` is still at `0.0.0` and
 * nothing stamps a build id into the bundle. Stated once here so that when the
 * web app does start carrying a release version there is a single place to
 * wire it up, rather than a literal buried in a form.
 */
export const WEB_APP_VERSION = '0.0.0'

const DEVICE_ID_KEY = 'wallet-bot-device-id'

/**
 * A stable per-browser id, used as the rate-limit key for the public feedback
 * endpoints. Without one every browser would share the anonymous bucket and
 * legitimate users would rate-limit each other.
 *
 * Deliberately random app state, not a fingerprint — the same posture as
 * native's `resolveDeviceId`. Returns `null` when storage is unavailable
 * (private mode, blocked cookies); the caller still works, it just falls into
 * the shared bucket, which is stricter rather than looser.
 */
export function resolveWebDeviceId(): string | null {
    try {
        const existing = localStorage.getItem(DEVICE_ID_KEY)
        if (existing !== null && existing.trim().length > 0) return existing

        const created = crypto.randomUUID()
        localStorage.setItem(DEVICE_ID_KEY, created)
        return created
    } catch {
        return null
    }
}
