import { useEffect, useState } from 'react'
import { Button } from '@/components/ui/button'
import {
    Dialog,
    DialogContent,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

export type CategoryFormValue = {
    name: string
}

export function CategoryDialog({
    open,
    onOpenChange,
    title,
    submitLabel,
    initialValue,
    onSubmit,
    onDelete,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    title: string
    submitLabel: string
    initialValue?: CategoryFormValue
    onSubmit: (value: CategoryFormValue) => Promise<void>
    onDelete?: () => Promise<void>
}) {
    const [name, setName] = useState('')
    const [submitting, setSubmitting] = useState(false)

    useEffect(() => {
        if (open) {
            setName(initialValue?.name ?? '')
        }
    }, [open, initialValue])

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault()
        const trimmed = name.trim()
        if (!trimmed) return
        setSubmitting(true)
        try {
            await onSubmit({ name: trimmed })
        } finally {
            setSubmitting(false)
        }
    }

    const handleDelete = async () => {
        if (!onDelete) return
        setSubmitting(true)
        try {
            await onDelete()
        } finally {
            setSubmitting(false)
        }
    }

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>{title}</DialogTitle>
                </DialogHeader>
                <form onSubmit={handleSubmit} className="flex flex-col gap-4">
                    <div className="flex flex-col gap-2">
                        <Label htmlFor="category-name">Name</Label>
                        <Input
                            id="category-name"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            autoFocus
                            required
                        />
                    </div>

                    <DialogFooter>
                        {onDelete ? (
                            <Button
                                type="button"
                                variant="destructive"
                                onClick={handleDelete}
                                disabled={submitting}
                            >
                                Delete
                            </Button>
                        ) : null}
                        <Button
                            type="button"
                            variant="outline"
                            onClick={() => onOpenChange(false)}
                            disabled={submitting}
                        >
                            Cancel
                        </Button>
                        <Button
                            type="submit"
                            disabled={submitting || !name.trim()}
                        >
                            {submitLabel}
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    )
}
