import type { ReactNode } from 'react'
import { useWindowSizeClass } from '@/hooks/use-window-size-class'
import { BottomSheet } from './bottom-sheet'

type DividedViewProps = {
    /**
     * The always-visible view. On expanded windows it becomes the left half of
     * the divided view.
     */
    list: ReactNode
    /**
     * The detail for the current selection, or null when nothing is selected.
     * Rendered inline in the right pane on expanded windows, and as a modal
     * bottom sheet on everything smaller.
     */
    detail: ReactNode
    /** Accessible name for the sheet presentation of the detail. */
    detailTitle: string
    /** Shown in the right pane when nothing is selected. */
    placeholder: ReactNode
    onDismiss: () => void
}

/**
 * The large-screen divided view, mirroring `AdaptiveDetailView` in the native
 * app (apps/native/lib/shared/adaptive_detail_view.dart).
 *
 * - **Small windows: nothing changes.** The list renders full-width and the
 *   detail is presented as a modal bottom sheet.
 * - **Expanded windows: the divided view.** The list takes the left half, a
 *   full-height divider follows, and the detail renders inline in the right
 *   half — never an overlay on top.
 *
 * Both presentations mount the same `detail` node, so a selection carried
 * across a resize keeps rendering; the sheet is simply not mounted while the
 * pane is showing.
 */
export function DividedView({
    list,
    detail,
    detailTitle,
    placeholder,
    onDismiss,
}: DividedViewProps) {
    const split = useWindowSizeClass() === 'expanded'

    if (split) {
        return (
            <div className="flex min-h-0 flex-1">
                <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
                    {list}
                </div>
                <div
                    aria-hidden
                    className="w-px shrink-0 self-stretch bg-outline-variant"
                />
                <div className="flex min-w-0 flex-1 flex-col overflow-y-auto">
                    {detail ?? placeholder}
                </div>
            </div>
        )
    }

    return (
        <>
            <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
                {list}
            </div>
            <BottomSheet
                open={detail !== null}
                onOpenChange={(open) => {
                    if (!open) onDismiss()
                }}
                title={detailTitle}
            >
                {detail}
            </BottomSheet>
        </>
    )
}
