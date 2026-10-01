import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { CategoryIcon } from '@/components/category-icon'
import {
    ConfirmDeleteDialog,
    DetailActionsRow,
    DetailColorEditor,
    MonthlySpendHero,
} from '@/components/entity-detail-sections'
import { EntityRecentTransactions } from '@/components/entity-recent-transactions'
import { IconPicker } from '@/components/icon-picker'
import { DetailPaneHeader } from '@/components/m3/detail-pane-header'
import { Input } from '@/components/ui/input'
import { useOccurrenceCutoff } from '@/hooks/use-occurrence-cutoff'
import { useSeededEntity } from '@/hooks/use-seeded-entity'
import { useToastMutation } from '@/hooks/use-toast-mutation'
import { CATEGORY_ICONS } from '@/lib/category-icons'
import { CATEGORY_DEFAULT_COLOR, normalizeColor } from '@/lib/entity-colors'
import { groupedRadius } from '@/lib/grouped-list'
import { useT } from '@/lib/i18n'
import { currentMonthWindow } from '@/lib/month-window'
import type { ActivityFilterSeed } from '@/pages/activity/helpers'

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

    const asOfMs = useOccurrenceCutoff()
    const spend = useQuery(api.v1.categories.queries.spendByCurrency, {
        id: category.id,
        ...currentMonthWindow(),
        asOfMs,
    })
    const recent = useQuery(api.v1.categories.queries.recentTransactions, {
        id: category.id,
        limit: 5,
        asOfMs,
    })

    const { fields, setFields, editing, setEditing } = useSeededEntity(
        category.id,
        () => ({
            name: category.name,
            color: normalizeColor(category.color, CATEGORY_DEFAULT_COLOR),
            icon: category.icon ?? 'category',
        }),
    )
    const { pending: saving, run } = useToastMutation()
    const [deleteOpen, setDeleteOpen] = useState(false)

    const accent = editing
        ? fields.color
        : normalizeColor(category.color, CATEGORY_DEFAULT_COLOR)

    const handleToggleEditing = () => {
        if (!editing) {
            setEditing(true)
            return
        }
        const trimmed = fields.name.trim()
        if (!trimmed) {
            toast.error(t.common.nameCannotBeEmpty)
            return
        }
        void run(
            updateCategory({
                id: category.id,
                name: trimmed,
                color: fields.color,
                icon: fields.icon,
            }),
            {
                loading: t.insights.categorySaving,
                success: t.insights.categorySaved,
                error: t.insights.categorySaveFailed,
            },
            () => setEditing(false),
        )
    }

    const handleDelete = () => {
        void run(
            archiveCategory({ id: category.id }),
            {
                loading: t.insights.categoryDeleting,
                success: t.insights.categoryDeleted,
                error: t.insights.categoryDeleteFailed,
            },
            () => {
                setDeleteOpen(false)
                onClose()
            },
        )
    }

    const viewAllTransactions = () => {
        onClose()
        const seed: ActivityFilterSeed = { categoryIds: [category.id] }
        navigate('/activity', { state: seed })
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
                            icon={fields.icon}
                            color={fields.color}
                            onIconChange={(icon) =>
                                setFields((current) => ({ ...current, icon }))
                            }
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
                            value={fields.name}
                            onChange={(e) =>
                                setFields((current) => ({
                                    ...current,
                                    name: e.target.value,
                                }))
                            }
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

                <DetailColorEditor
                    editing={editing}
                    color={fields.color}
                    onChange={(color) =>
                        setFields((current) => ({ ...current, color }))
                    }
                />

                <MonthlySpendHero
                    label={t.insights.spentThisMonth}
                    spend={spend}
                />

                <DetailActionsRow
                    editing={editing}
                    saving={saving}
                    onToggleEditing={handleToggleEditing}
                    onDelete={() => setDeleteOpen(true)}
                />

                <EntityRecentTransactions
                    title={t.insights.lastMovements}
                    viewAllLabel={t.insights.viewAll}
                    onViewAll={viewAllTransactions}
                    transactions={recent}
                />

                <ConfirmDeleteDialog
                    open={deleteOpen}
                    onOpenChange={setDeleteOpen}
                    title={t.insights.categoryDeleteTitle}
                    description={t.insights.categoryDeleteConfirm({
                        name: category.name,
                    })}
                    saving={saving}
                    onDelete={handleDelete}
                />
            </div>
        </div>
    )
}
