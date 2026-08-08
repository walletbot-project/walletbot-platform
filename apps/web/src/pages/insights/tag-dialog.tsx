import { Check } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { Combobox } from '@/components/ui/combobox'
import {
    Dialog,
    DialogContent,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useT } from '@/lib/i18n'
import {
    normalizeTagColor,
    TAG_COLOR_OPTIONS,
    TAG_DEFAULT_COLOR,
} from '@/lib/tag-colors'
import { cn } from '@/lib/utils'

export type TagFormValue = {
    name: string
    color: string
    parentId: string | null
}

export type TagOption = {
    id: string
    name: string
    color?: string
    parentId?: string
}

export function TagDialog({
    open,
    onOpenChange,
    title,
    submitLabel,
    initialValue,
    parentOptions,
    onSubmit,
    onDelete,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    title: string
    submitLabel: string
    initialValue?: TagFormValue
    parentOptions: TagOption[]
    onSubmit: (value: TagFormValue) => Promise<void>
    onDelete?: () => Promise<void>
}) {
    const t = useT()
    const [name, setName] = useState('')
    const [color, setColor] = useState(TAG_DEFAULT_COLOR)
    const [isSubtag, setIsSubtag] = useState(false)
    const [parentId, setParentId] = useState<string | null>(null)
    const [submitting, setSubmitting] = useState(false)

    useEffect(() => {
        if (open) {
            setName(initialValue?.name ?? '')
            setColor(normalizeTagColor(initialValue?.color))
            const startParent = initialValue?.parentId ?? null
            setParentId(startParent)
            setIsSubtag(startParent !== null)
        }
    }, [open, initialValue])

    const comboboxOptions = useMemo(
        () =>
            parentOptions.map((p) => ({
                value: p.id,
                label: p.name,
            })),
        [parentOptions],
    )

    const canShowSubtag = parentOptions.length > 0

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault()
        const trimmed = name.trim()
        if (!trimmed) return
        if (isSubtag && !parentId) return
        setSubmitting(true)
        try {
            await onSubmit({
                name: trimmed,
                color,
                parentId: isSubtag ? parentId : null,
            })
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
                        <Label htmlFor="tag-name">{t.common.name}</Label>
                        <Input
                            id="tag-name"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            autoFocus
                            required
                        />
                    </div>
                    <div className="flex flex-col gap-2">
                        <Label>{t.common.color}</Label>
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
                                        aria-label={t.common.colorSwatch({
                                            color: option,
                                        })}
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

                    {canShowSubtag ? (
                        <div className="flex items-center gap-2">
                            <Checkbox
                                id="tag-is-subtag"
                                checked={isSubtag}
                                onCheckedChange={(checked) => {
                                    const next = checked === true
                                    setIsSubtag(next)
                                    if (!next) setParentId(null)
                                }}
                            />
                            <Label htmlFor="tag-is-subtag">
                                {t.insights.createSubtag}
                            </Label>
                        </div>
                    ) : null}

                    {isSubtag && canShowSubtag ? (
                        <div className="flex flex-col gap-2">
                            <Label>{t.insights.parentTag}</Label>
                            <Combobox
                                value={parentId ? [parentId] : []}
                                onChange={(values) =>
                                    setParentId(values[0] ?? null)
                                }
                                options={comboboxOptions}
                                placeholder={t.insights.selectParentTag}
                                searchPlaceholder={t.insights.searchTags}
                                emptyMessage={t.insights.noTagsAvailable}
                                className="w-full"
                            />
                        </div>
                    ) : null}

                    <DialogFooter>
                        {onDelete ? (
                            <Button
                                type="button"
                                variant="destructive"
                                onClick={handleDelete}
                                disabled={submitting}
                            >
                                {t.common.delete}
                            </Button>
                        ) : null}
                        <Button
                            type="button"
                            variant="outline"
                            onClick={() => onOpenChange(false)}
                            disabled={submitting}
                        >
                            {t.common.cancel}
                        </Button>
                        <Button
                            type="submit"
                            disabled={
                                submitting ||
                                !name.trim() ||
                                (isSubtag && !parentId)
                            }
                        >
                            {submitLabel}
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    )
}
