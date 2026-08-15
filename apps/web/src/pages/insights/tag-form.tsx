import { Button, CircularProgress, TextField } from 'actify'
import { type FormEvent, useMemo, useState } from 'react'
import { ColorSwatches } from '@/components/color-swatches'
import { FormScreen } from '@/components/m3/form-screen'
import { OptionSheet, type SheetOption } from '@/components/m3/option-sheet'
import { PickerField } from '@/components/m3/picker-field'
import { Checkbox } from '@/components/ui/checkbox'
import { Label } from '@/components/ui/label'
import { useT } from '@/lib/i18n'
import {
    normalizeTagColor,
    TAG_COLOR_OPTIONS,
    TAG_DEFAULT_COLOR,
} from '@/lib/tag-colors'

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

/**
 * Tag creation. Like the account and category forms it renders in the divided
 * view's pane on expanded windows and over the window on smaller ones.
 */
export function TagForm({
    title,
    submitLabel,
    initialValue,
    parentOptions,
    onClose,
    onSubmit,
}: {
    title: string
    submitLabel: string
    initialValue?: TagFormValue
    parentOptions: TagOption[]
    onClose: () => void
    onSubmit: (value: TagFormValue) => Promise<void>
}) {
    const t = useT()
    const [name, setName] = useState(initialValue?.name ?? '')
    const [color, setColor] = useState(
        normalizeTagColor(initialValue?.color ?? TAG_DEFAULT_COLOR),
    )
    const [parentId, setParentId] = useState<string | null>(
        initialValue?.parentId ?? null,
    )
    const [isSubtag, setIsSubtag] = useState(
        (initialValue?.parentId ?? null) !== null,
    )
    const [parentOpen, setParentOpen] = useState(false)
    const [submitting, setSubmitting] = useState(false)

    const canShowSubtag = parentOptions.length > 0

    const parentSheetOptions: SheetOption[] = useMemo(
        () => parentOptions.map((p) => ({ id: p.id, label: p.name })),
        [parentOptions],
    )

    const handleSubmit = async (event: FormEvent) => {
        event.preventDefault()
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

    return (
        <FormScreen title={title} onClose={onClose}>
            <form onSubmit={handleSubmit} className="flex flex-col gap-6 p-4">
                <TextField
                    variant="outlined"
                    className="w-full"
                    label={t.common.name}
                    value={name}
                    onChange={setName}
                    isRequired
                    isDisabled={submitting}
                    autoFocus
                />

                <section className="flex flex-col gap-3">
                    <h2 className="m3-label-large text-on-surface">
                        {t.common.color}
                    </h2>
                    <ColorSwatches
                        value={color}
                        onChange={setColor}
                        options={TAG_COLOR_OPTIONS}
                    />
                </section>

                {canShowSubtag ? (
                    <div className="flex items-center gap-3">
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
                    <PickerField
                        label={t.insights.parentTag}
                        value={
                            parentOptions.find((p) => p.id === parentId)
                                ?.name ?? ''
                        }
                        placeholder={t.insights.selectParentTag}
                        onClick={() => setParentOpen(true)}
                        disabled={submitting}
                    />
                ) : null}

                <Button
                    type="submit"
                    variant="filled"
                    className="w-full"
                    isDisabled={
                        submitting || !name.trim() || (isSubtag && !parentId)
                    }
                >
                    {submitting ? (
                        <CircularProgress isIndeterminate size="xs" />
                    ) : null}
                    {submitLabel}
                </Button>
            </form>

            <OptionSheet
                open={parentOpen}
                onOpenChange={setParentOpen}
                title={t.insights.selectParentTag}
                options={parentSheetOptions}
                selected={parentId}
                onSelect={(id) => {
                    setParentId(id)
                    setParentOpen(false)
                }}
                searchPlaceholder={t.insights.searchTags}
                emptyMessage={t.insights.noTagsAvailable}
            />
        </FormScreen>
    )
}
