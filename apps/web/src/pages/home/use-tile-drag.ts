import {
    type PointerEvent as ReactPointerEvent,
    useEffect,
    useRef,
    useState,
} from 'react'

/** Where a dragged tile would land if it were dropped right now. */
export type DropTarget =
    | { kind: 'tile'; id: string }
    | { kind: 'cell'; row: number; col: number }

export type TileDrag = {
    /** Id of the tile being dragged. */
    id: string
    /** Pointer position in viewport coordinates, for the drag preview. */
    x: number
    y: number
    /** Width of the tile at pick-up, so the preview matches what was grabbed. */
    width: number
    over: DropTarget | null
}

/**
 * Mouse drag slop, from `_ImmediateDragPointerState._slop`. A tile is also a
 * tap target, so at the browser's own click tolerance a click carrying a pixel
 * of hand jitter would turn into a drag that lands back on itself and swallows
 * the selection.
 */
const MOUSE_SLOP = 6
/** Flutter's `kTouchSlop`. */
const TOUCH_SLOP = 18
/** Flutter's `kLongPressTimeout`. */
const TOUCH_HOLD_MS = 500

type Pending = {
    id: string
    pointerId: number
    startX: number
    startY: number
    width: number
    isMouse: boolean
    timer: number | null
}

/**
 * Resolves the drop target under the pointer. Targets mark themselves with
 * `data-drop-*` attributes rather than being registered up front, so a row that
 * reflows mid-drag needs no bookkeeping. `elementsFromPoint` skips anything
 * with `pointer-events: none`, which is why the drag preview never shadows the
 * board underneath it.
 */
function targetAt(x: number, y: number, draggedId: string): DropTarget | null {
    for (const element of document.elementsFromPoint(x, y)) {
        if (!(element instanceof HTMLElement)) continue
        const { dropKind, dropId, dropRow, dropCol } = element.dataset
        if (dropKind === 'tile' && dropId !== undefined) {
            // Dropping a tile on itself is a no-op, and it must not shadow the
            // gap targets underneath it either.
            return dropId === draggedId ? null : { kind: 'tile', id: dropId }
        }
        if (
            dropKind === 'cell' &&
            dropRow !== undefined &&
            dropCol !== undefined
        ) {
            return { kind: 'cell', row: Number(dropRow), col: Number(dropCol) }
        }
    }
    return null
}

/**
 * Pointer-driven drag-and-drop for the dashboard tiles, with the device
 * trade-off the native board settles on (`_MouseFriendlyDraggable`).
 *
 * - **A mouse drags straight away**, as soon as it travels past
 *   [MOUSE_SLOP]. Waiting out a half-second hold on every tile reads as
 *   "dragging is broken" on desktop, and a mouse cannot scroll the page by
 *   dragging anyway, so the hold buys nothing.
 * - **Touch and stylus keep the hold.** The dashboard sits inside the scrolling
 *   home page; a finger that starts dragging immediately would take the page's
 *   scroll away everywhere a tile sits. Move before the hold elapses and the
 *   gesture is released back to the page. Once a touch drag is live, a
 *   non-passive `touchmove` listener holds the scroll off — pointer events
 *   alone cannot.
 *
 * Escape and `pointercancel` abandon the drag without a drop.
 */
export function useTileDrag(onDrop: (id: string, target: DropTarget) => void) {
    const [drag, setDrag] = useState<TileDrag | null>(null)
    const dragRef = useRef<TileDrag | null>(null)
    const stopRef = useRef<(() => void) | null>(null)
    /**
     * Whether the pointer sequence that just ended became a drag. The tile is a
     * selection target too, and the browser still fires its `click` after the
     * drag's `pointerup`.
     */
    const draggedRef = useRef(false)
    const onDropRef = useRef(onDrop)

    useEffect(() => {
        onDropRef.current = onDrop
    })

    // Nothing survives unmount: a board that goes away mid-drag must not leave
    // window listeners or a frozen cursor behind.
    useEffect(() => () => stopRef.current?.(), [])

    const dragging = drag !== null
    useEffect(() => {
        if (!dragging) return
        const { body } = document
        const previousCursor = body.style.cursor
        const previousUserSelect = body.style.userSelect
        body.style.cursor = 'grabbing'
        body.style.userSelect = 'none'
        return () => {
            body.style.cursor = previousCursor
            body.style.userSelect = previousUserSelect
        }
    }, [dragging])

    const startTracking = (
        event: ReactPointerEvent<HTMLElement>,
        id: string,
    ) => {
        if (event.button !== 0) return
        stopRef.current?.()
        draggedRef.current = false

        const pending: Pending = {
            id,
            pointerId: event.pointerId,
            startX: event.clientX,
            startY: event.clientY,
            width: event.currentTarget.getBoundingClientRect().width,
            isMouse: event.pointerType === 'mouse',
            timer: null,
        }

        const stop = () => {
            if (pending.timer !== null) window.clearTimeout(pending.timer)
            window.removeEventListener('pointermove', handleMove)
            window.removeEventListener('pointerup', handleUp)
            window.removeEventListener('pointercancel', handleCancel)
            window.removeEventListener('keydown', handleKey)
            window.removeEventListener('touchmove', blockScroll)
            dragRef.current = null
            stopRef.current = null
            setDrag(null)
        }

        const finish = (target: DropTarget | null) => {
            const active = dragRef.current
            stop()
            if (active && target) onDropRef.current(active.id, target)
        }

        const begin = (x: number, y: number) => {
            if (pending.timer !== null) window.clearTimeout(pending.timer)
            draggedRef.current = true
            const started: TileDrag = {
                id,
                x,
                y,
                width: pending.width,
                over: targetAt(x, y, id),
            }
            dragRef.current = started
            setDrag(started)
        }

        function handleMove(moveEvent: PointerEvent) {
            if (moveEvent.pointerId !== pending.pointerId) return
            const active = dragRef.current
            if (active) {
                const next: TileDrag = {
                    ...active,
                    x: moveEvent.clientX,
                    y: moveEvent.clientY,
                    over: targetAt(moveEvent.clientX, moveEvent.clientY, id),
                }
                dragRef.current = next
                setDrag(next)
                return
            }
            const distance = Math.hypot(
                moveEvent.clientX - pending.startX,
                moveEvent.clientY - pending.startY,
            )
            if (pending.isMouse) {
                if (distance > MOUSE_SLOP) {
                    begin(moveEvent.clientX, moveEvent.clientY)
                }
            } else if (distance > TOUCH_SLOP) {
                // The finger is scrolling the page, not rearranging the board.
                stop()
            }
        }

        function handleUp(upEvent: PointerEvent) {
            if (upEvent.pointerId !== pending.pointerId) return
            finish(dragRef.current?.over ?? null)
        }

        function handleCancel(cancelEvent: PointerEvent) {
            if (cancelEvent.pointerId !== pending.pointerId) return
            stop()
        }

        function handleKey(keyEvent: KeyboardEvent) {
            if (keyEvent.key === 'Escape') stop()
        }

        function blockScroll(touchEvent: TouchEvent) {
            if (dragRef.current) touchEvent.preventDefault()
        }

        window.addEventListener('pointermove', handleMove)
        window.addEventListener('pointerup', handleUp)
        window.addEventListener('pointercancel', handleCancel)
        window.addEventListener('keydown', handleKey)
        window.addEventListener('touchmove', blockScroll, { passive: false })
        stopRef.current = stop

        if (!pending.isMouse) {
            pending.timer = window.setTimeout(
                () => begin(pending.startX, pending.startY),
                TOUCH_HOLD_MS,
            )
        }
    }

    return {
        drag,
        startTracking,
        /** True when the click about to fire is the tail of a drag. */
        wasDragged: () => draggedRef.current,
    }
}
