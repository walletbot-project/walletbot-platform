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
    /**
     * A creation/edit form, or null when none is open. It occupies the same
     * pane as the detail on expanded windows and covers the window on smaller
     * ones. The pane hosts one occupant at a time: callers must clear the
     * selection when opening the form and vice versa; when both are set the
     * form wins.
     */
    form?: ReactNode
}

/**
 * The large-screen divided view, mirroring `AdaptiveDetailView` in the native
 * app (apps/native/lib/shared/adaptive_detail_view.dart).
 *
 * - **Small windows: nothing changes.** The list renders full-width, the
 *   detail is presented as a modal bottom sheet, and a form covers the window
 *   the way the native pushed route does.
 * - **Expanded windows: the divided view.** The list takes the left half, a
 *   full-height divider follows, and the form or detail renders inline in the
 *   right half — never an overlay on top.
 *
 * Both presentations mount the same nodes, so a selection carried across a
 * resize keeps rendering; only the framing around it changes.
 */
export function DividedView({
    list,
    detail,
    detailTitle,
    placeholder,
    onDismiss,
    form = null,
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
                {/*
                 * A form brings its own app bar and scroller (`FormScreen`);
                 * a detail is plain content, so the pane scrolls it — with the
                 * detail's own close bar sticking to the top as it does.
                 */}
                <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
                    {form ?? (
                        <div className="flex min-h-0 flex-1 flex-col overflow-y-auto">
                            {detail ?? placeholder}
                        </div>
                    )}
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
                open={detail !== null && form === null}
                onOpenChange={(open) => {
                    if (!open) onDismiss()
                }}
                title={detailTitle}
            >
                {detail}
            </BottomSheet>
            {/*
             * The form takes over the whole window, the navigation bar
             * included — the same thing the native pushed route does.
             */}
            {form === null ? null : (
                <div className="fixed inset-0 z-50 flex flex-col bg-surface">
                    {form}
                </div>
            )}
        </>
    )
}
