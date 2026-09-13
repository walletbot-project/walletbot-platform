import { pastCutoffBigInt } from '@wallet-bot/shared'

// Older web bundles omit the cutoff. They remain callable, but their cached
// subscriptions need a normal data invalidation or reload to cross a boundary.
export function resolveOccurrenceCutoff(asOfMs?: bigint): bigint {
    return asOfMs ?? pastCutoffBigInt()
}
