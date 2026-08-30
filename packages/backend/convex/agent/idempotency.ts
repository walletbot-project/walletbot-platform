// Deterministic entity ids, so a replayed agent turn writes nothing twice.
//
// R-039: a WhatsApp turn is at-least-once. `runAgentTurn` claims a batch,
// generates, sends, and only then calls `finishBatch`; if the action dies in
// between, the reaper returns those messages to `pending` and the agent runs
// again on the same input. With read-only tools that cost a repeated reply.
// With write tools it would cost a second expense the user never asked for —
// which is why the risk register made this a precondition for shipping them.
//
// The fix is to make the *identity* of what the agent creates a function of
// the turn rather than of chance. Instead of `crypto.randomUUID()`, a create
// derives its client id from a seed built out of the claimed message ids, the
// tool name, and which call of that tool it is. A replay of the same batch
// therefore lands on the same id, and the "already exists" check in each
// create turns the second write into a no-op.
//
// What this does *not* fix — deliberately — is the duplicate reply. The user
// may see the same confirmation twice after a crash; that was already the
// accepted cost in R-039, and it is visible and harmless, unlike a duplicate
// movement.

// Stable across a replay because the rows are the same rows: the reaper flips
// their status back to `pending`, it does not recreate them. Sorted so a
// different claim order cannot change the key.
export const turnKeyFor = (messageIds: readonly string[]): string =>
    [...messageIds].sort().join(',')

// Seed for one write within a turn. `nth` counts calls *of that tool*, not all
// calls, so a replay that happens to interleave a different number of reads
// still maps its first `addExpense` onto the first `addExpense` of the
// original turn.
export const writeKeyFor = (
    turnKey: string,
    toolName: string,
    nth: number,
): string => `${turnKey}|${toolName}|${nth}`

const hex = (bytes: Uint8Array): string =>
    Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')

// A UUID-shaped, RFC-4122-conformant identifier derived from `seed`.
//
// Shaped like a UUID because every other writer of these tables produces one
// (the app, the native database, the sync engine) and a differently shaped id
// would be a lasting oddity in the data for no benefit. Version nibble 8 and
// the standard variant bits mark it honestly as name-based rather than random.
export const deterministicId = async (seed: string): Promise<string> => {
    const digest = await crypto.subtle.digest(
        'SHA-256',
        new TextEncoder().encode(seed),
    )
    const bytes = new Uint8Array(digest).slice(0, 16)
    bytes[6] = (bytes[6] & 0x0f) | 0x80 // version 8 (custom / name-based)
    bytes[8] = (bytes[8] & 0x3f) | 0x80 // RFC 4122 variant
    const value = hex(bytes)
    return [
        value.slice(0, 8),
        value.slice(8, 12),
        value.slice(12, 16),
        value.slice(16, 20),
        value.slice(20, 32),
    ].join('-')
}

// The id a create should use: derived when the caller supplied a write key,
// random otherwise. `runForUser` and any future non-replayable caller pass
// nothing and keep the old behaviour.
export const newEntityId = async (
    writeKey: string | undefined,
): Promise<string> =>
    writeKey === undefined
        ? crypto.randomUUID()
        : await deterministicId(writeKey)
