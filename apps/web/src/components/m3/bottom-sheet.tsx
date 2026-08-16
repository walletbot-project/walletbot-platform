import { Dialog } from '@base-ui/react/dialog'
import type { ReactNode } from 'react'
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
    className?: string
}

/**
 * A modal surface whose framing follows the window size class, porting
 * `showAdaptiveModal` (apps/native/lib/shared/adaptive_modal.dart).
 *
 * - **Compact windows: a Material 3 modal bottom sheet** — drag handle, 28dp
 *   top corners, and a `surfaceContainerLow` container that stops short of the
 *   top of the window. The 640px cap is Material's own: Flutter's
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
 */
export function BottomSheet({
    open,
    onOpenChange,
    title,
    showTitle = false,
    dialogPadded = true,
    children,
    className,
}: BottomSheetProps) {
    const asDialog = useWindowSizeClass() !== 'compact'

    return (
        <Dialog.Root open={open} onOpenChange={onOpenChange}>
            <Dialog.Portal>
                {/* The scrim the rest of the app's overlays use. */}
                <Dialog.Backdrop className="fixed inset-0 z-50 bg-black/10 transition-opacity duration-150 supports-backdrop-filter:backdrop-blur-xs data-ending-style:opacity-0 data-starting-style:opacity-0" />
                <Dialog.Viewport
                    className={cn(
                        'fixed inset-0 z-50 flex justify-center',
                        asDialog ? 'items-center p-6' : 'items-end',
                    )}
                >
                    <Dialog.Popup
                        className={cn(
                            'flex w-full min-w-0 flex-col overflow-hidden text-on-surface outline-none transition duration-200 ease-out data-ending-style:opacity-0 data-starting-style:opacity-0',
                            asDialog
                                ? cn(
                                      'max-h-[80dvh] max-w-140 rounded-[28px] bg-surface-container-high shadow-level-3 data-ending-style:scale-95 data-starting-style:scale-95',
                                      dialogPadded && 'py-4',
                                  )
                                : 'max-h-[95dvh] max-w-160 rounded-t-[28px] bg-surface-container-low data-ending-style:translate-y-10 data-starting-style:translate-y-10',
                            className,
                        )}
                    >
                        {asDialog ? null : (
                            <div className="flex justify-center pt-4 pb-2">
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
