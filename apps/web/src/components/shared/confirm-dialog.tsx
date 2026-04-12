import { t } from '@wallet-bot/shared'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import {
    Dialog,
    DialogClose,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'

interface ConfirmDialogProps {
    open: boolean
    onOpenChange: (open: boolean) => void
    title: string
    description: string
    confirmLabel?: string
    variant?: 'default' | 'destructive'
    onConfirm: () => void | Promise<void>
}

export function ConfirmDialog({
    open,
    onOpenChange,
    title,
    description,
    confirmLabel,
    variant = 'destructive',
    onConfirm,
}: ConfirmDialogProps) {
    const [loading, setLoading] = useState(false)

    const handleConfirm = async () => {
        setLoading(true)
        try {
            await onConfirm()
            onOpenChange(false)
        } finally {
            setLoading(false)
        }
    }

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>{title}</DialogTitle>
                    <DialogDescription>{description}</DialogDescription>
                </DialogHeader>
                <DialogFooter>
                    <DialogClose>
                        <Button variant="outline" disabled={loading}>
                            {t('common.cancel')}
                        </Button>
                    </DialogClose>
                    <Button
                        variant={variant}
                        onClick={handleConfirm}
                        disabled={loading}
                    >
                        {loading
                            ? t('common.loading')
                            : (confirmLabel ?? t('common.confirm'))}
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    )
}
