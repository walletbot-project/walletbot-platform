import type { ReactNode } from 'react'
import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet'
import { cn } from '@/lib/utils'

type BottomSheetProps = {
    open: boolean
    onOpenChange: (open: boolean) => void
    /** Accessible name; rendered visually only when `showTitle` is set. */
    title: string
    showTitle?: boolean
    children: ReactNode
    className?: string
}

/**
 * A Material 3 modal bottom sheet: drag handle, 28dp top corners, and a
 * `surfaceContainerLow` container that stops short of the top of the window —
 * the same framing `showModalBottomSheet` gives the native detail sheets.
 *
 * The 640px cap is Material 3's own: Flutter's `_BottomSheetDefaultsM3` gives
 * every modal sheet `BoxConstraints(maxWidth: 640)`, so on wide windows the
 * sheet is a centred column rather than a full-bleed band.
 */
export function BottomSheet({
    open,
    onOpenChange,
    title,
    showTitle = false,
    children,
    className,
}: BottomSheetProps) {
    return (
        <Sheet open={open} onOpenChange={onOpenChange}>
            <SheetContent
                side="bottom"
                showCloseButton={false}
                className={cn(
                    'mx-auto max-h-[95dvh] w-full max-w-160 gap-0 rounded-t-[28px] border-none bg-surface-container-low p-0 text-on-surface',
                    className,
                )}
            >
                <div className="flex justify-center pt-4 pb-2">
                    <span
                        aria-hidden
                        className="h-1 w-8 rounded-full bg-on-surface-variant/40"
                    />
                </div>
                <SheetTitle
                    className={cn(
                        'm3-title-large px-4 text-on-surface',
                        showTitle ? 'pb-2' : 'sr-only',
                    )}
                >
                    {title}
                </SheetTitle>
                <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">
                    {children}
                </div>
            </SheetContent>
        </Sheet>
    )
}
