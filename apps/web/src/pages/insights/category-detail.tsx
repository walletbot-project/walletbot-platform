import { api } from '@wallet-bot/backend/api'
import { Button, IconButton } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { CategoryIcon } from '@/components/category-icon'
import { ColorSwatches } from '@/components/color-swatches'
import { EntityRecentTransactions } from '@/components/entity-recent-transactions'
import { IconPicker } from '@/components/icon-picker'
import { DetailPaneHeader } from '@/components/m3/detail-pane-header'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { Icon } from '@/components/m3/icon'
import { MonthlySpend } from '@/components/monthly-spend'
import { Input } from '@/components/ui/input'
import { CATEGORY_ICONS } from '@/lib/category-icons'
import {
    CATEGORY_DEFAULT_COLOR,
    COLOR_OPTIONS,
    normalizeColor,
} from '@/lib/entity-colors'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { useT } from '@/lib/i18n'

export type CategorySummary = {
    id: string
    name: string
    icon?: string
    color?: string
    description?: string
}

/**
 * A category's details, laid out like the native `CategoryDetailsSheet`: a
 * color-washed identity hero joined to the monthly-spend hero, an edit/delete
 * action row, and the five most recent transactions.
 *
 * Presentation-agnostic — `ListDetailLayout` renders it inline in the split pane on
 * expanded windows and inside a modal bottom sheet everywhere else.
 */
export function CategoryDetail({
    category,
    onClose,
}: {
    category: CategorySummary
    onClose: () => void
}) {
    const navigate = useNavigate()
    const t = useT()
    const updateCategory = useMutation(api.v1.categories.mutations.update)
    const archiveCategory = useMutation(api.v1.categories.mutations.archive)

    const [monthWindow] = useState(() => {
        const now = new Date()
        const from = new Date(now.getFullYear(), now.getMonth(), 1)
        const to = new Date(now.getFullYear(), now.getMonth() + 1, 1)
        return {
            fromMs: BigInt(from.getTime()),
            toExclusiveMs: BigInt(to.getTime()),
        }
    })

    const spend = useQuery(api.v1.categories.queries.spendByCurrency, {
        id: category.id,
        ...monthWindow,
    })
    const recent = useQuery(api.v1.categories.queries.recentTransactions, {
        id: category.id,
        limit: 5,
    })

    const [editing, setEditing] = useState(false)
    const [saving, setSaving] = useState(false)
    const [name, setName] = useState(category.name)
    const [color, setColor] = useState(
        normalizeColor(category.color, CATEGORY_DEFAULT_COLOR),
    )
    const [icon, setIcon] = useState(category.icon ?? 'category')
    const [deleteOpen, setDeleteOpen] = useState(false)

    // Re-seed the editable identity only when a *different* category opens.
    // Keying on the id (not the object) keeps live query updates — e.g. the
    // refreshed values right after a save — from clobbering in-progress edits.
    const [seededId, setSeededId] = useState(category.id)
    useEffect(() => {
        if (category.id === seededId) return
        setSeededId(category.id)
        setName(category.name)
        setColor(normalizeColor(category.color, CATEGORY_DEFAULT_COLOR))
        setIcon(category.icon ?? 'category')
        setEditing(false)
    }, [category, seededId])

    const accent = editing
        ? color
        : normalizeColor(category.color, CATEGORY_DEFAULT_COLOR)

    const handleToggleEditing = async () => {
        if (!editing) {
            setEditing(true)
            return
        }
        const trimmed = name.trim()
        if (!trimmed) {
            toast.error(t.common.nameCannotBeEmpty)
            return
        }
        setSaving(true)
        const promise = updateCategory({
            id: category.id,
            name: trimmed,
            color,
            icon,
        })
        toast.promise(promise, {
            loading: t.insights.categorySaving,
            success: t.insights.categorySaved,
            error: t.insights.categorySaveFailed,
        })
        try {
            await promise
            setEditing(false)
        } finally {
            setSaving(false)
        }
    }

    const handleDelete = async () => {
        setSaving(true)
        const promise = archiveCategory({ id: category.id })
        toast.promise(promise, {
            loading: t.insights.categoryDeleting,
            success: t.insights.categoryDeleted,
            error: t.insights.categoryDeleteFailed,
        })
        try {
            await promise
            setDeleteOpen(false)
            onClose()
        } finally {
            setSaving(false)
        }
    }

    const viewAllTransactions = () => {
        onClose()
        navigate('/activity', { state: { categoryIds: [category.id] } })
    }

    return (
        <div className="flex flex-col pb-6">
            <DetailPaneHeader
                title={t.insights.categoryDetails}
                onClose={onClose}
            />
            <div className="flex flex-col px-4">
                {/* Identity hero — tinted by the category's accent color. */}
                <div
                    className="flex items-center gap-4 p-5"
                    style={{
                        backgroundColor: `${accent}24`,
                        ...groupedRadius(0, 2),
                    }}
                >
                    {editing ? (
                        <IconPicker
                            icon={icon}
                            color={color}
                            onIconChange={setIcon}
                            icons={CATEGORY_ICONS}
                        />
                    ) : (
                        <span
                            className="flex size-15 shrink-0 items-center justify-center rounded-[20px]"
                            style={{ backgroundColor: `${accent}47` }}
                        >
                            <CategoryIcon
                                name={category.icon}
                                size={30}
                                color={accent}
                            />
                        </span>
                    )}
                    {editing ? (
                        <Input
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            className="bg-surface"
                            aria-label={t.common.name}
                        />
                    ) : (
                        <div className="flex min-w-0 flex-1 flex-col">
                            <span className="m3-title-large truncate font-semibold">
                                {category.name}
                            </span>
                            {category.description ? (
                                <span className="m3-body-medium truncate text-on-surface-variant">
                                    {category.description}
                                </span>
                            ) : null}
                        </div>
                    )}
                </div>

                {editing ? (
                    <div className="pt-3">
                        <ColorSwatches
                            value={color}
                            onChange={setColor}
                            options={COLOR_OPTIONS}
                        />
                    </div>
                ) : null}

                {/* Monthly spend hero. */}
                <div
                    className="flex flex-col gap-1 bg-surface-container-high px-5 pt-4 pb-4.5"
                    style={{ marginTop: GROUP_SPACING, ...groupedRadius(1, 2) }}
                >
                    <span className="m3-label-medium tracking-[0.8px] text-on-surface-variant">
                        {t.insights.spentThisMonth.toUpperCase()}
                    </span>
                    <MonthlySpend spend={spend} />
                </div>

                {/* Actions. */}
                <div className="mt-3 flex items-center gap-2">
                    <Button
                        variant={editing ? 'filled' : 'tonal'}
                        className="flex-1"
                        onPress={handleToggleEditing}
                        isDisabled={saving}
                    >
                        <Icon name={editing ? 'check' : 'edit'} size={18} />
                        {editing ? t.common.done : t.common.edit}
                    </Button>
                    <IconButton
                        onPress={() => setDeleteOpen(true)}
                        isDisabled={saving}
                        aria-label={t.common.delete}
                        className="rounded-full bg-error-container text-on-error-container"
                    >
                        <Icon name="delete" />
                    </IconButton>
                </div>

                <EntityRecentTransactions
                    title={t.insights.lastMovements}
                    viewAllLabel={t.insights.viewAll}
                    onViewAll={viewAllTransactions}
                    transactions={recent}
                />

                <M3Dialog
                    open={deleteOpen}
                    onOpenChange={setDeleteOpen}
                    title={t.insights.categoryDeleteTitle}
                    description={t.insights.categoryDeleteConfirm({
                        name: category.name,
                    })}
                    actions={
                        <>
                            <DialogAction
                                label={t.common.cancel}
                                onPress={() => setDeleteOpen(false)}
                                isDisabled={saving}
                            />
                            <DialogAction
                                label={t.common.delete}
                                onPress={handleDelete}
                                isDisabled={saving}
                                destructive
                            />
                        </>
                    }
                />
            </div>
        </div>
    )
}
