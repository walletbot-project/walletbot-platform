import { Check } from 'lucide-react'
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
import {
    normalizeTagColor,
    TAG_COLOR_OPTIONS,
    TAG_DEFAULT_COLOR,
} from '@/lib/tag-colors'
import { cn } from '@/lib/utils'

export type TagFormValue = {
    name: string
    color: string
}

export function TagDialog({
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
    initialValue?: TagFormValue
    onSubmit: (value: TagFormValue) => Promise<void>
    onDelete?: () => Promise<void>
}) {
    const [name, setName] = useState('')
    const [color, setColor] = useState(TAG_DEFAULT_COLOR)
    const [submitting, setSubmitting] = useState(false)

    useEffect(() => {
        if (open) {
            setName(initialValue?.name ?? '')
            setColor(normalizeTagColor(initialValue?.color))
        }
    }, [open, initialValue])

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault()
        const trimmed = name.trim()
        if (!trimmed) return
        setSubmitting(true)
        try {
            await onSubmit({ name: trimmed, color })
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
                        <Label htmlFor="tag-name">Name</Label>
                        <Input
                            id="tag-name"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            autoFocus
                            required
                        />
                    </div>
                    <div className="flex flex-col gap-2">
                        <Label>Color</Label>
                        <div className="flex flex-wrap gap-2">
                            {TAG_COLOR_OPTIONS.map((option) => {
                                const isSelected = option === color
                                return (
                                    <button
                                        type="button"
                                        key={option}
                                        onClick={() => setColor(option)}
                                        className={cn(
                                            'flex size-9 items-center justify-center rounded-full border-2 transition-transform',
                                            isSelected
                                                ? 'border-foreground'
                                                : 'border-transparent hover:scale-105',
                                        )}
                                        style={{ backgroundColor: option }}
                                        aria-label={`Color ${option}`}
                                        aria-pressed={isSelected}
                                    >
                                        {isSelected ? (
                                            <Check className="size-4 text-foreground" />
                                        ) : null}
                                    </button>
                                )
                            })}
                        </div>
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
