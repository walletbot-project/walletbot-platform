import type { ReactNode } from 'react'
import { useMatches, useNavigate, useOutlet } from 'react-router-dom'
import { useWindowSizeClass } from '@/hooks/use-window-size-class'
import { cn } from '@/lib/utils'
import { BottomSheet } from './bottom-sheet'

type ListDetailLayoutProps = {
    /** The always-visible list. Left half of the split on expanded windows. */
    list: ReactNode
    /** Right-pane filler on expanded windows when nothing is open. */
    placeholder: ReactNode
    /** Accessible name for the detail's modal presentation. */
    detailTitle: string
    /** The list's own URL. Closing the occupant navigates here. */
    closeTo: string
    /**
     * Handed to the child route through `useOutletContext`. The way a detail
     * talks back to its list without either of them owning the other's state.
     */
    context?: unknown
}

/** A child route sets `handle: { fullScreen: true }` to present as a page. */
function wantsFullScreen(handle: unknown): boolean {
    return (
        typeof handle === 'object' &&
        handle !== null &&
        'fullScreen' in handle &&
        handle.fullScreen === true
    )
}

/**
 * The list-detail shell for Accounts, Activity and Insights.
 *
 * **What is open is the URL's business.** Which child route matched decides
 * whether a detail, a creation form, or nothing is showing — read here through
 * `useOutlet()`. No component state is involved, so nothing can drop it: not a
 * re-render, not a resize, not a remount. Reload, back/forward and deep links
 * work without being designed for.
 *
 * **Presentation below the split is unchanged from how this app has always
 * behaved**, deliberately:
 *
 * - A **creation form** covers the window (`fixed inset-0`), as a page. It is
 *   never a bottom sheet.
 * - A **detail** is presented in `BottomSheet`, which is a sheet on compact and
 *   a dialog from medium up.
 * - **Expanded (>= 1000px)** is the divided view: list | divider | occupant.
 *
 * A form renders in the same element in both the full-window and the split
 * framing, so crossing 1000px mid-form re-styles it in place and keeps every
 * field. (A detail still moves between this element and the sheet's portal when
 * crossing 1000px, which does remount it — pre-existing behaviour, left alone
 * rather than silently redesigned.)
 */
export function ListDetailLayout({
    list,
    placeholder,
    detailTitle,
    closeTo,
    context,
}: ListDetailLayoutProps) {
    const outlet = useOutlet(context)
    const matches = useMatches()
    const navigate = useNavigate()
    const split = useWindowSizeClass() === 'expanded'
    const open = outlet !== null
    const fullScreen = matches.some((match) => wantsFullScreen(match.handle))

    // Below the split, a form takes the window and a detail takes the sheet.
    const inSheet = open && !split && !fullScreen
    const asPage = open && !split && fullScreen

    return (
        <div className="flex min-h-0 flex-1">
            <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
                {list}
            </div>

            {split ? (
                <div
                    aria-hidden
                    className="w-px shrink-0 self-stretch bg-outline-variant"
                />
            ) : null}

            {/*
             * The occupant slot: the split pane and the full-window form are
             * the same element wearing different classes, never two branches.
             * Two branches is what used to unmount a half-filled form on
             * resize. Do not wrap this in a conditional.
             */}
            <div
                data-occupant
                className={cn(
                    'flex flex-col overflow-hidden',
                    split && 'min-w-0 flex-1',
                    asPage && 'fixed inset-0 z-50 bg-surface',
                    !split && !asPage && 'hidden',
                )}
            >
                <div className="flex min-h-0 flex-1 flex-col overflow-y-auto">
                    {inSheet ? null : (outlet ?? (split ? placeholder : null))}
                </div>
            </div>

            <BottomSheet
                open={inSheet}
                onOpenChange={(next) => {
                    if (!next) navigate(closeTo)
                }}
                title={detailTitle}
                // The detail heads itself with an app bar, so the dialog
                // framing adds no inset of its own.
                dialogPadded={false}
            >
                {inSheet ? outlet : null}
            </BottomSheet>
        </div>
    )
}
