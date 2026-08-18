import type { PointerEvent as ReactPointerEvent } from 'react'
import { useCallback, useEffect, useRef, useState } from 'react'

/** Downward travel past which releasing dismisses the sheet. */
const DISMISS_TRAVEL_PX = 88
/** Fraction of a sheet's own height that also dismisses, for short sheets. */
const DISMISS_RATIO = 0.3
/** Kept in sync with the sheet's CSS transition duration. */
const SHEET_EXIT_MS = 200

type SheetDismissOptions = {
    /** Whether the surface is currently presented as a draggable sheet. */
    enabled: boolean
    /** Run once the exit transition has played out. */
    onDismissed: () => void
}

/**
 * Drag-to-dismiss for a modal bottom sheet, and the slide-out that every close
 * path shares.
 *
 * The sheet's vertical position is driven by an offset, never by a
 * mount/unmount swap: the surface stays in the tree and only moves. That is
 * what lets a close animate at all — the content is still there while it
 * slides — and it is why a resize can never destroy the sheet's contents.
 *
 * Every dismissal (drag, scrim, Escape, close button) goes through `dismiss`,
 * so the surface always leaves the same way instead of blinking out.
 */
export function useSheetDismiss({ enabled, onDismissed }: SheetDismissOptions) {
    const sheetRef = useRef<HTMLDivElement>(null)
    const [offset, setOffset] = useState(0)
    const [dragging, setDragging] = useState(false)
    const startY = useRef(0)
    const exitTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

    const clearExit = useCallback(() => {
        if (exitTimer.current !== null) {
            clearTimeout(exitTimer.current)
            exitTimer.current = null
        }
    }, [])

    useEffect(() => clearExit, [clearExit])

    // The callbacks live in a ref so the effect below doesn't re-run (and the
    // exit timer isn't disturbed) when a consumer passes a fresh closure.
    const onDismissedRef = useRef(onDismissed)
    useEffect(() => {
        onDismissedRef.current = onDismissed
    }, [onDismissed])

    useEffect(() => {
        if (enabled) return
        if (exitTimer.current !== null) {
            // The surface stopped being a sheet mid-exit (the window crossed
            // the breakpoint): the slide can't finish, so complete the
            // dismissal now instead of resurrecting a surface the user
            // already dismissed.
            clearExit()
            onDismissedRef.current()
        }
    }, [enabled, clearExit])

    // A surface that stops being a sheet (the window grew into the split, or it
    // closed) must not keep a stale drag offset for its next presentation.
    // Adjusted during render rather than in an effect — React's own guidance for
    // deriving state from a changed prop, and it avoids a frame where the sheet
    // would be drawn at the offset it was dismissed with.
    const [wasEnabled, setWasEnabled] = useState(enabled)
    if (wasEnabled !== enabled) {
        setWasEnabled(enabled)
        if (!enabled) {
            setDragging(false)
            setOffset(0)
        }
    }

    const sheetHeight = useCallback(
        () => sheetRef.current?.getBoundingClientRect().height ?? 0,
        [],
    )

    const dismiss = useCallback(() => {
        if (!enabled) {
            onDismissed()
            return
        }
        const height = sheetHeight()
        setDragging(false)
        // Slide the whole surface past the bottom edge, then let the caller
        // change the URL — the content stays mounted for the whole slide.
        setOffset(height > 0 ? height : window.innerHeight)
        clearExit()
        exitTimer.current = setTimeout(() => {
            exitTimer.current = null
            onDismissed()
        }, SHEET_EXIT_MS)
    }, [enabled, onDismissed, clearExit, sheetHeight])

    const onPointerDown = useCallback(
        (event: ReactPointerEvent<HTMLElement>) => {
            if (!enabled || event.button !== 0) return
            startY.current = event.clientY
            setDragging(true)
            event.currentTarget.setPointerCapture(event.pointerId)
        },
        [enabled],
    )

    const onPointerMove = useCallback(
        (event: ReactPointerEvent<HTMLElement>) => {
            if (!dragging) return
            // Downward only: a sheet cannot be flung above its resting place.
            setOffset(Math.max(0, event.clientY - startY.current))
        },
        [dragging],
    )

    const endDrag = useCallback(
        (event: ReactPointerEvent<HTMLElement>) => {
            if (!dragging) return
            setDragging(false)
            const travelled = Math.max(0, event.clientY - startY.current)
            const height = sheetHeight()
            const threshold =
                height > 0
                    ? Math.min(DISMISS_TRAVEL_PX, height * DISMISS_RATIO)
                    : DISMISS_TRAVEL_PX
            if (travelled >= threshold) dismiss()
            else setOffset(0)
        },
        [dragging, dismiss, sheetHeight],
    )

    return {
        sheetRef,
        offset,
        dragging,
        dismiss,
        /** Spread onto the drag handle. */
        handleProps: {
            onPointerDown,
            onPointerMove,
            onPointerUp: endDrag,
            onPointerCancel: endDrag,
        },
    }
}
