import { useState } from 'react'

/**
 * Editable identity state seeded from the open entity, re-seeded only when a
 * *different* entity opens. Keying on the id keeps live query updates — e.g.
 * the refreshed values right after a save — from clobbering in-progress edits.
 *
 * The adjustment happens during render (React's own guidance for deriving
 * state from a changed prop), so switching entities never paints one frame of
 * the previous entity's half-edited values — the old effect-based reseed did.
 */
export function useSeededEntity<Fields>(id: string, seed: () => Fields) {
    const [fields, setFields] = useState(seed)
    const [editing, setEditing] = useState(false)
    const [seededId, setSeededId] = useState(id)
    if (seededId !== id) {
        setSeededId(id)
        setFields(seed())
        setEditing(false)
    }
    return { fields, setFields, editing, setEditing }
}
