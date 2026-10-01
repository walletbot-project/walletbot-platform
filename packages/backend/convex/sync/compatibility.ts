import { compareVersions } from '../config/utils'

/** Feature capability, independent of the minimum supported app version. */
export function supportsRecurrences(
    platform?: string,
    version?: string,
): boolean {
    return (
        platform === 'web' || compareVersions(version ?? '0.0.0', '0.4.0') >= 0
    )
}
