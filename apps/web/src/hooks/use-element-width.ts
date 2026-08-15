import { useCallback, useEffect, useRef, useState } from 'react'

/**
 * The measured content width of an element, the web stand-in for Flutter's
 * `LayoutBuilder`: layouts that reflow on their *own* width — not the window's —
 * need the box, not a media query.
 *
 * Returns `null` until the first measurement, so callers can hold off rendering
 * a width-dependent layout rather than flashing the wrong one.
 */
export function useElementWidth(): [
    (node: HTMLElement | null) => void,
    number | null,
] {
    const [width, setWidth] = useState<number | null>(null)
    const observerRef = useRef<ResizeObserver | null>(null)

    const ref = useCallback((node: HTMLElement | null) => {
        observerRef.current?.disconnect()
        if (!node) {
            observerRef.current = null
            return
        }
        setWidth(node.getBoundingClientRect().width)
        const observer = new ResizeObserver((entries) => {
            const entry = entries[0]
            if (entry) setWidth(entry.contentRect.width)
        })
        observer.observe(node)
        observerRef.current = observer
    }, [])

    useEffect(() => () => observerRef.current?.disconnect(), [])

    return [ref, width]
}
