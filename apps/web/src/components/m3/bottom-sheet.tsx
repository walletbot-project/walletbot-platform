import { Dialog } from '@base-ui/react/dialog'
import type { CSSProperties, ReactNode } from 'react'
import { useCallback } from 'react'
import { useSheetDismiss } from '@/hooks/use-sheet-dismiss'
import { useWindowSizeClass } from '@/hooks/use-window-size-class'
import { cn } from '@/lib/utils'

type BottomSheetProps = {
    open: boolean
    onOpenChange: (open: boolean) => void
    /** Accessible name; rendered visually only when `showTitle` is set. */
    title: string
    showTitle?: boolean
    /**
     * Whether the dialog framing keeps its vertical inset. Clear it for content
     * that brings its own top chrome — a detail pane's app bar — the way
     * `AdaptiveDetailView` passes `padding: EdgeInsets.zero` for the same case.
     */
    dialogPadded?: boolean
    children: ReactNode
}

/**
 * A modal surface whose framing follows the window size class, porting
 * `showAdaptiveModal` (apps/native/lib/shared/adaptive_modal.dart).
 *
 * - **Compact windows: a Material 3 modal bottom sheet** — drag handle, 28dp
 *   top corners, and a `surfaceContainerLow` container that stops short of the
 *   top of the window. It slides its full height in and out, and the handle
 *   drags it down to dismiss. The 640px cap is Material's own: Flutter's
 *   `_BottomSheetDefaultsM3` gives every modal sheet
 *   `BoxConstraints(maxWidth: 640)`.
 * - **Medium and expanded windows: a Material 3 dialog** — centred,
 *   `surfaceContainerHigh` at elevation 3, at Material's 560dp dialog width and
 *   the 80%-of-window height cap the native dialog framing uses. The drag
 *   handle gives way to the vertical inset that framing adds in its place;
 *   without it, a body written for a sheet renders flush against the rounded
 *   corners.
 *
 * Both framings are one Base UI dialog wearing different chrome, so crossing
 * the breakpoint with a surface open re-styles it where it stands: no remount,
 * and the content keeps its state — a half-typed search included — the way the
 * native route swap keeps its `GlobalKey`'d subtree alive. Going through the
 * primitive rather than `components/ui`'s `Sheet` and `Dialog` wrappers is what
 * buys that; they are two different components, so swapping between them would
 * throw the content away and rebuild it.
 *
 * This surface is for transient pickers only. Anything that is a *screen* — a
 * detail, a creation form — belongs to a route instead; see
 * `ListDetailLayout`.
 */
export function BottomSheet({
    open,
    onOpenChange,
    title,
    showTitle = false,
    dialogPadded = true,
    children,
}: BottomSheetProps) {
    const asDialog = useWindowSizeClass() !== 'compact'
    const close = useCallback(() => onOpenChange(false), [onOpenChange])
    const { sheetRef, offset, dragging, dismiss, handleProps } =
        useSheetDismiss({
            enabled: !asDialog && open,
            onDismissed: close,
        })

    // Only take the transform over while the user is actually moving the
    // sheet. At rest it must stay unset so the entry and exit transitions —
    // which Base UI drives through data-starting-style / data-ending-style —
    // are not overridden by an inline `translateY(0)`.
    const dragStyle: CSSProperties | undefined =
        offset > 0 || dragging
            ? {
                  transform: `translateY(${offset}px)`,
                  transition: dragging ? 'none' : undefined,
              }
            : undefined

    return (
        <Dialog.Root
            open={open}
            onOpenChange={(next) => {
                // Every close request — scrim, Escape, a consumer's close
                // button — funnels through `dismiss`, so a sheet always slides
                // out with its content still mounted, exactly like the drag
                // path. (As a dialog, `dismiss` closes immediately.)
                if (next) onOpenChange(true)
                else dismiss()
            }}
        >
            <Dialog.Portal>
                {/* The scrim the rest of the app's overlays use. */}
                <Dialog.Backdrop className="fixed inset-0 z-50 bg-scrim/30 transition-opacity duration-200 supports-backdrop-filter:backdrop-blur-xs data-ending-style:opacity-0 data-starting-style:opacity-0" />
                <Dialog.Viewport
                    className={cn(
                        'fixed inset-0 z-50 flex justify-center',
                        asDialog ? 'items-center p-6' : 'items-end',
                    )}
                >
                    <Dialog.Popup
                        ref={sheetRef}
                        style={dragStyle}
                        className={cn(
                            'flex w-full min-w-0 flex-col overflow-hidden text-on-surface outline-none transition duration-200 ease-out data-ending-style:opacity-0 data-starting-style:opacity-0',
                            asDialog
                                ? cn(
                                      'max-h-[80dvh] max-w-140 rounded-[28px] bg-surface-container-high shadow-level-3 data-ending-style:scale-95 data-starting-style:scale-95',
                                      dialogPadded && 'py-4',
                                  )
                                : // A sheet travels its own full height, not a
                                  // token nudge — anything less reads as a jump.
                                  'max-h-[95dvh] max-w-160 rounded-t-[28px] bg-surface-container-low shadow-level-3 data-ending-style:translate-y-full data-starting-style:translate-y-full',
                        )}
                    >
                        {asDialog ? null : (
                            <div
                                {...handleProps}
                                className="flex shrink-0 cursor-grab touch-none justify-center pt-4 pb-2 active:cursor-grabbing"
                            >
                                <span
                                    aria-hidden
                                    className="h-1 w-8 rounded-full bg-on-surface-variant/40"
                                />
                            </div>
                        )}
                        <Dialog.Title
                            className={cn(
                                'm3-title-large px-4 text-on-surface',
                                showTitle ? 'pb-2' : 'sr-only',
                            )}
                        >
                            {title}
                        </Dialog.Title>
                        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">
                            {children}
                        </div>
                    </Dialog.Popup>
                </Dialog.Viewport>
            </Dialog.Portal>
        </Dialog.Root>
    )
}
