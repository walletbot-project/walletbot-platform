/// The parts of a voice session row that a client can change. `userId` and
/// `sessionId` are the index keys the row is found by, so they never differ
/// between what is stored and what arrives.
export type SessionSnapshot = {
    model: string
    status: string
    startedAt: bigint
    updatedAt: bigint
    endedAt?: bigint
    endedExplicitly: boolean
}

/// Whether an incoming session payload differs from the stored row.
///
/// `appendEvents` used to patch the session document on every call, so two
/// batches for the same session overlapped write sets and conflicted under
/// OCC, which made sending them concurrently slower than sending them one at
/// a time. Batches replicating one session all carry the same payload, so
/// after the first lands the rest compare equal and touch the document only
/// as a read.
export function sessionFieldsChanged(
    stored: SessionSnapshot,
    incoming: SessionSnapshot,
): boolean {
    return (
        stored.model !== incoming.model ||
        stored.status !== incoming.status ||
        stored.startedAt !== incoming.startedAt ||
        stored.updatedAt !== incoming.updatedAt ||
        stored.endedAt !== incoming.endedAt ||
        stored.endedExplicitly !== incoming.endedExplicitly
    )
}
