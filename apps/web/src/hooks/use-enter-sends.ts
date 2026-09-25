import { type KeyboardEvent, useCallback, useEffect, useRef } from 'react'

const HOLD_SAMPLES = 5
const PHYSICAL_HOLD_MS = 25

function editsText(event: globalThis.KeyboardEvent) {
    return (
        event.key.length === 1 ||
        event.key === 'Enter' ||
        event.key === 'Backspace'
    )
}

/**
 * Browsers don't say which keyboard a key came from, so it is inferred.
 * On-screen keyboards deliver each key's press and release together: Gboard
 * reports 0 ms for Enter, and iOS a few ms, while a physical key stays down
 * for tens of ms. Gboard's letters also carry an empty `code`, which no
 * physical key does. Until a key has been timed, a coarse primary pointer (a
 * touch screen) stands in for an on-screen keyboard.
 */
function isOnScreenKeyboard(
    event: globalThis.KeyboardEvent,
    holds: readonly number[],
) {
    if (event.code === '') return true
    if (holds.length === 0) return matchMedia('(pointer: coarse)').matches
    const average = holds.reduce((sum, hold) => sum + hold, 0) / holds.length
    return average < PHYSICAL_HOLD_MS
}

/**
 * The chat composer's Enter rule, shared with the native composer: a physical
 * keyboard sends on Enter and breaks the line on Shift+Enter, while an
 * on-screen keyboard always breaks the line and the send button sends.
 *
 * Returns a predicate for the composer's `keydown`: `true` means send.
 */
export function useEnterSends() {
    const holds = useRef<number[]>([])

    useEffect(() => {
        const pressed = new Map<string, number>()
        const down = (event: globalThis.KeyboardEvent) => {
            if (event.repeat || !editsText(event)) return
            pressed.set(event.code || event.key, event.timeStamp)
        }
        const up = (event: globalThis.KeyboardEvent) => {
            const key = event.code || event.key
            const start = pressed.get(key)
            if (start === undefined) return
            pressed.delete(key)
            holds.current = [
                ...holds.current.slice(1 - HOLD_SAMPLES),
                event.timeStamp - start,
            ]
        }
        document.addEventListener('keydown', down, true)
        document.addEventListener('keyup', up, true)
        return () => {
            document.removeEventListener('keydown', down, true)
            document.removeEventListener('keyup', up, true)
        }
    }, [])

    return useCallback(
        (event: KeyboardEvent) =>
            event.key === 'Enter' &&
            !event.shiftKey &&
            !event.nativeEvent.isComposing &&
            (event.metaKey ||
                event.ctrlKey ||
                !isOnScreenKeyboard(event.nativeEvent, holds.current)),
        [],
    )
}
