import { Button, IconButton } from 'actify'
import type { ComponentProps } from 'react'
import { ColorSwatches } from '@/components/color-swatches'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { Icon } from '@/components/m3/icon'
import { MonthlySpend } from '@/components/monthly-spend'
import { COLOR_OPTIONS } from '@/lib/entity-colors'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { useT } from '@/lib/i18n'

/** The color-swatch row a detail shows under its hero while editing. */
export function DetailColorEditor({
    editing,
    color,
    onChange,
}: {
    editing: boolean
    color: string
    onChange: (color: string) => void
}) {
    if (!editing) return null
    return (
        <div className="pt-3">
            <ColorSwatches
                value={color}
                onChange={onChange}
                options={COLOR_OPTIONS}
            />
        </div>
    )
}

/** The "SPENT THIS MONTH" hero the category and tag details share. */
export function MonthlySpendHero({
    label,
    spend,
}: {
    label: string
    spend: ComponentProps<typeof MonthlySpend>['spend']
}) {
    return (
        <div
            className="flex flex-col gap-1 bg-surface-container-high px-5 pt-4 pb-4.5"
            style={{ marginTop: GROUP_SPACING, ...groupedRadius(1, 2) }}
        >
            <span className="m3-label-medium tracking-[0.8px] text-on-surface-variant">
                {label.toUpperCase()}
            </span>
            <MonthlySpend spend={spend} />
        </div>
    )
}

/** The edit-toggle + delete action row the category and tag details share. */
export function DetailActionsRow({
    editing,
    saving,
    onToggleEditing,
    onDelete,
}: {
    editing: boolean
    saving: boolean
    onToggleEditing: () => void
    onDelete: () => void
}) {
    const t = useT()
    return (
        <div className="mt-3 flex items-center gap-2">
            <Button
                variant={editing ? 'filled' : 'tonal'}
                className="flex-1"
                onPress={onToggleEditing}
                isDisabled={saving}
            >
                <Icon name={editing ? 'check' : 'edit'} size={18} />
                {editing ? t.common.done : t.common.edit}
            </Button>
            <IconButton
                onPress={onDelete}
                isDisabled={saving}
                aria-label={t.common.delete}
                className="rounded-full bg-error-container text-on-error-container"
            >
                <Icon name="delete" />
            </IconButton>
        </div>
    )
}

/** The plain cancel/delete confirmation dialog (tag's cascade one is its own). */
export function ConfirmDeleteDialog({
    open,
    onOpenChange,
    title,
    description,
    saving,
    onDelete,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    title: string
    description: string
    saving: boolean
    onDelete: () => void
}) {
    const t = useT()
    return (
        <M3Dialog
            open={open}
            onOpenChange={onOpenChange}
            title={title}
            description={description}
            actions={
                <>
                    <DialogAction
                        label={t.common.cancel}
                        onPress={() => onOpenChange(false)}
                        isDisabled={saving}
                    />
                    <DialogAction
                        label={t.common.delete}
                        onPress={onDelete}
                        isDisabled={saving}
                        destructive
                    />
                </>
            }
        />
    )
}
