/**
 * How a client identifies itself when it has no backend user.
 *
 * Native local accounts are unauthenticated by design, so the anonymous paths
 * (`v1/feedback/mutations`, `POST /v1/live/token`) key their rate limits on a
 * device id the client generates once and persists
 * (`apps/native/lib/app_config/device_id.dart`). That id is spoofable, which is
 * why every anonymous path carries a global ceiling as well.
 */

/**
 * Cap on the client-supplied device id. `ClientInfo.deviceId` is a uuid;
 * anything longer is a client bug or an attempt to bloat the rate limiter's key
 * space.
 */
export const MAX_DEVICE_ID_LENGTH = 128

const UUID_PATTERN =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * Whether a device id is a real generated uuid. Native reports the literal
 * `'unknown'` when secure storage fails, which rate limits tolerate but
 * anything that scopes data ownership to the device must refuse: every broken
 * device would share one owner.
 */
export function isDeviceUuid(deviceId: string): boolean {
    return UUID_PATTERN.test(deviceId)
}
