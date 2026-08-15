import { api } from '@wallet-bot/backend/api'
import { Button, IconButton } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { ColorSwatches } from '@/components/color-swatches'
import { EntityRecentTransactions } from '@/components/entity-recent-transactions'
import { DetailPaneHeader } from '@/components/m3/detail-pane-header'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { Icon } from '@/components/m3/icon'
import { MonthlySpend } from '@/components/monthly-spend'
import { Input } from '@/components/ui/input'
import { COLOR_OPTIONS } from '@/lib/entity-colors'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { useT } from '@/lib/i18n'
import { normalizeTagColor } from '@/lib/tag-colors'

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
 * Presentation-agnostic — `DividedView` renders it inline in the split pane on
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

    const [monthWindow] = useState(() => {
        const now = new Date()
        const from = new Date(now.getFullYear(), now.getMonth(), 1)
        const to = new Date(now.getFullYear(), now.getMonth() + 1, 1)
        return {
            fromMs: BigInt(from.getTime()),
            toExclusiveMs: BigInt(to.getTime()),
        }
    })

    const spend = useQuery(api.v1.tags.queries.spendByCurrency, {
        id: tag.id,
        ...monthWindow,
    })
    const recent = useQuery(api.v1.tags.queries.recentTransactions, {
        id: tag.id,
        limit: 5,
    })

    const [editing, setEditing] = useState(false)
    const [saving, setSaving] = useState(false)
    const [name, setName] = useState(tag.name)
    const [color, setColor] = useState(normalizeTagColor(tag.color))
    const [deleteOpen, setDeleteOpen] = useState(false)

    // Re-seed the editable identity only when a *different* tag opens. Keying
    // on the id (not the object) keeps live query updates — e.g. the refreshed
    // values right after a save — from clobbering in-progress edits.
    const [seededId, setSeededId] = useState(tag.id)
    useEffect(() => {
        if (tag.id === seededId) return
        setSeededId(tag.id)
        setName(tag.name)
        setColor(normalizeTagColor(tag.color))
        setEditing(false)
    }, [tag, seededId])

    const accent = editing ? color : normalizeTagColor(tag.color)

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
        const promise = updateTag({ id: tag.id, name: trimmed, color })
        toast.promise(promise, {
            loading: t.insights.tagSaving,
            success: t.insights.tagSaved,
            error: t.insights.tagSaveFailed,
        })
        try {
            await promise
            setEditing(false)
        } finally {
            setSaving(false)
        }
    }

    const performDelete = async (cascade: boolean) => {
        setSaving(true)
        const promise = archiveTag({ id: tag.id, cascade })
        toast.promise(promise, {
            loading: t.insights.tagDeleting,
            success: t.insights.tagDeleted,
            error: t.insights.tagDeleteFailed,
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
        navigate('/activity', { state: { tagIds: [tag.id] } })
    }

    const hasChildren = childTags.length > 0

    return (
        <div className="flex flex-col pb-6">
            <DetailPaneHeader onClose={onClose} />
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
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            className="bg-surface"
                            aria-label={t.common.name}
                        />
                    ) : (
                        <span className="m3-title-large min-w-0 flex-1 truncate font-semibold">
                            {tag.name}
                        </span>
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
