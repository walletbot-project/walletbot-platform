import type { ReactNode } from 'react'
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import {
    Sheet,
    SheetContent,
    SheetDescription,
    SheetHeader,
    SheetTitle,
} from '@/components/ui/sheet'
import { useIsMobile } from '@/hooks/use-mobile'

interface ResponsiveDialogProps {
    open: boolean
    onOpenChange: (open: boolean) => void
    title: string
    description?: string
    children: ReactNode
}

export function ResponsiveDialog({
    open,
    onOpenChange,
    title,
    description,
    children,
}: ResponsiveDialogProps) {
    const isMobile = useIsMobile()

    if (isMobile) {
        return (
            <Sheet open={open} onOpenChange={onOpenChange}>
                <SheetContent
                    side="bottom"
                    className="max-h-[90vh] overflow-y-auto"
                >
                    <SheetHeader>
                        <SheetTitle>{title}</SheetTitle>
                        {description && (
                            <SheetDescription>{description}</SheetDescription>
                        )}
                    </SheetHeader>
                    <div className="px-4 pb-6 pt-4">{children}</div>
                </SheetContent>
            </Sheet>
        )
    }

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>{title}</DialogTitle>
                    {description && (
                        <DialogDescription>{description}</DialogDescription>
                    )}
                </DialogHeader>
                {children}
            </DialogContent>
        </Dialog>
    )
}
