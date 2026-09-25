import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
    DetailActionsRow,
    DetailColorEditor,
    MonthlySpendHero,
} from '@/components/entity-detail-sections'
import { EntityRecentTransactions } from '@/components/entity-recent-transactions'
import { DetailPaneHeader } from '@/components/m3/detail-pane-header'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { Input } from '@/components/ui/input'
import { useOccurrenceCutoff } from '@/hooks/use-occurrence-cutoff'
import { useSeededEntity } from '@/hooks/use-seeded-entity'
import { useToastMutation } from '@/hooks/use-toast-mutation'
import { groupedRadius } from '@/lib/grouped-list'
import { useT } from '@/lib/i18n'
import { currentMonthWindow } from '@/lib/month-window'
import { normalizeTagColor } from '@/lib/tag-colors'
import type { ActivityFilterSeed } from '@/pages/activity/helpers'

export type TagSummary = {
    id: string
    name: string
    color?: string
    parentId?: string
}

/**
 * A tag's details: a color-washed identity hero, the monthly-spend hero, an
 * edit/delete action row, and the five most recent transactions — the same
 * shape as the account and category details, matching the native tag sheet.
 *
 * Presentation-agnostic — `ListDetailLayout` renders it inline in the split pane on
 * expanded windows and inside a modal bottom sheet everywhere else.
 */
export function TagDetail({
    tag,
    childTags,
    onClose,
}: {
    tag: TagSummary
    /** Direct sub-tags, used to decide the delete flow. */
    childTags: TagSummary[]
    onClose: () => void
}) {
    const navigate = useNavigate()
    const t = useT()
    const updateTag = useMutation(api.v1.tags.mutations.update)
    const archiveTag = useMutation(api.v1.tags.mutations.archive)

    const asOfMs = useOccurrenceCutoff()
    const spend = useQuery(api.v1.tags.queries.spendByCurrency, {
        id: tag.id,
        ...currentMonthWindow(),
        asOfMs,
    })
    const recent = useQuery(api.v1.tags.queries.recentTransactions, {
        id: tag.id,
        limit: 5,
        asOfMs,
    })

    const { fields, setFields, editing, setEditing } = useSeededEntity(
        tag.id,
        () => ({
            name: tag.name,
            color: normalizeTagColor(tag.color),
        }),
    )
    const { pending: saving, run } = useToastMutation()
    const [deleteOpen, setDeleteOpen] = useState(false)

    const accent = editing ? fields.color : normalizeTagColor(tag.color)

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
            updateTag({ id: tag.id, name: trimmed, color: fields.color }),
            {
                loading: t.insights.tagSaving,
                success: t.insights.tagSaved,
                error: t.insights.tagSaveFailed,
            },
            () => setEditing(false),
        )
    }

    const performDelete = (cascade: boolean) => {
        void run(
            archiveTag({ id: tag.id, cascade }),
            {
                loading: t.insights.tagDeleting,
                success: t.insights.tagDeleted,
                error: t.insights.tagDeleteFailed,
            },
            () => {
                setDeleteOpen(false)
                onClose()
            },
        )
    }

    const viewAllTransactions = () => {
        onClose()
        const seed: ActivityFilterSeed = { tagIds: [tag.id] }
        navigate('/activity', { state: seed })
    }

    const hasChildren = childTags.length > 0

    return (
        <div className="flex flex-col pb-6">
            <DetailPaneHeader title={t.insights.tagDetails} onClose={onClose} />
            <div className="flex flex-col px-4">
                {/* Identity hero — tags have no icon, just a color wash. */}
                <div
                    className="flex items-center gap-3 p-5"
                    style={{
                        backgroundColor: `${accent}24`,
                        ...groupedRadius(0, 2),
                    }}
                >
                    <span
                        className="size-3 shrink-0 rounded-full"
                        style={{ backgroundColor: accent }}
                    />
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
                        <span className="m3-title-large min-w-0 flex-1 truncate font-semibold">
                            {tag.name}
                        </span>
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

                <M3Dialog
                    open={deleteOpen}
                    onOpenChange={setDeleteOpen}
                    title={
                        hasChildren
                            ? t.insights.tagDeleteWithChildrenTitle
                            : t.insights.tagDeleteTitle
                    }
                    description={
                        hasChildren
                            ? undefined
                            : t.insights.tagDeleteConfirm({ name: tag.name })
                    }
                    actions={
                        <>
                            <DialogAction
                                label={t.common.cancel}
                                onPress={() => setDeleteOpen(false)}
                                isDisabled={saving}
                            />
                            {hasChildren ? (
                                <DialogAction
                                    label={t.insights.keepSubtags}
                                    onPress={() => performDelete(false)}
                                    isDisabled={saving}
                                />
                            ) : null}
                            <DialogAction
                                label={
                                    hasChildren
                                        ? t.insights.deleteEverything
                                        : t.common.delete
                                }
                                onPress={() => performDelete(hasChildren)}
                                isDisabled={saving}
                                destructive
                            />
                        </>
                    }
                >
                    {hasChildren ? (
                        <div className="m3-body-medium flex flex-col gap-3 text-on-surface-variant">
                            <p>
                                <span className="font-medium text-on-surface">
                                    {tag.name}
                                </span>{' '}
                                {t.insights.tagDeleteWithChildrenPrompt({
                                    count: childTags.length,
                                })}
                            </p>
                            <ul className="list-disc pl-5">
                                {childTags.map((child) => (
                                    <li key={child.id}>{child.name}</li>
                                ))}
                            </ul>
                        </div>
                    ) : null}
                </M3Dialog>
            </div>
        </div>
    )
}
