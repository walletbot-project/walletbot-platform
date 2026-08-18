import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { Check, Pencil, Trash2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { ColorSwatches } from '@/components/color-swatches'
import { EntityRecentTransactions } from '@/components/entity-recent-transactions'
import { MonthlySpend } from '@/components/monthly-spend'
import { Button } from '@/components/ui/button'
import {
    Dialog,
    DialogContent,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet'
import { COLOR_OPTIONS } from '@/lib/entity-colors'
import { useT } from '@/lib/i18n'
import { normalizeTagColor } from '@/lib/tag-colors'

export type TagSummary = {
    id: string
    name: string
    color?: string
    parentId?: string
}

export function TagDetailsSheet({
    tag,
    childTags,
    open,
    onOpenChange,
}: {
    tag: TagSummary | null
    /** Direct sub-tags, used to decide the delete flow. */
    childTags: TagSummary[]
    open: boolean
    onOpenChange: (open: boolean) => void
}) {
    const navigate = useNavigate()
    const t = useT()
    const updateTag = useMutation(api.v1.tags.mutations.update)
    const archiveTag = useMutation(api.v1.tags.mutations.archive)

    const tagId = tag?.id ?? ''
    const [monthWindow] = useState(() => {
        const now = new Date()
        const from = new Date(now.getFullYear(), now.getMonth(), 1)
        const to = new Date(now.getFullYear(), now.getMonth() + 1, 1)
        return {
            fromMs: BigInt(from.getTime()),
            toExclusiveMs: BigInt(to.getTime()),
        }
    })

    const spend = useQuery(
        api.v1.tags.queries.spendByCurrency,
        tag ? { id: tagId, ...monthWindow } : 'skip',
    )
    const recent = useQuery(
        api.v1.tags.queries.recentTransactions,
        tag ? { id: tagId, limit: 5 } : 'skip',
    )

    const [editing, setEditing] = useState(false)
    const [saving, setSaving] = useState(false)
    const [name, setName] = useState('')
    const [color, setColor] = useState(normalizeTagColor(undefined))
    const [deleteOpen, setDeleteOpen] = useState(false)

    // Re-seed the editable identity only when a *different* tag opens. Keying
    // on the id (not the object) keeps live query updates — e.g. the refreshed
    // values right after a save — from clobbering in-progress edits.
    const [seededId, setSeededId] = useState<string | null>(null)
    useEffect(() => {
        const id = tag?.id ?? null
        if (id === seededId) return
        setSeededId(id)
        if (tag) {
            setName(tag.name)
            setColor(normalizeTagColor(tag.color))
            setEditing(false)
        }
    }, [tag, seededId])

    if (!tag) return null

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
            onOpenChange(false)
        } finally {
            setSaving(false)
        }
    }

    const requestDelete = () => {
        // No sub-tags → straight confirm; otherwise ask what happens to them.
        setDeleteOpen(true)
    }

    const viewAllTransactions = () => {
        onOpenChange(false)
        navigate('/activity', { state: { tagIds: [tag.id] } })
    }

    const hasChildren = childTags.length > 0

    return (
        <Sheet open={open} onOpenChange={onOpenChange}>
            <SheetContent side="right" className="w-full gap-0 p-0 sm:max-w-md">
                <SheetTitle className="sr-only">{tag.name}</SheetTitle>
                <div className="flex flex-1 flex-col gap-3 overflow-y-auto p-4">
                    {/* Identity hero — tags have no icon, just a color wash. */}
                    <div
                        className="flex items-center gap-3 rounded-2xl p-5"
                        style={{ backgroundColor: `${accent}24` }}
                    >
                        <span
                            className="size-3 shrink-0 rounded-full"
                            style={{ backgroundColor: accent }}
                        />
                        {editing ? (
                            <Input
                                value={name}
                                onChange={(e) => setName(e.target.value)}
                                className="bg-background"
                                aria-label={t.common.name}
                            />
                        ) : (
                            <span className="min-w-0 flex-1 truncate text-xl font-semibold">
                                {tag.name}
                            </span>
                        )}
                    </div>

                    {editing ? (
                        <ColorSwatches
                            value={color}
                            onChange={setColor}
                            options={COLOR_OPTIONS}
                        />
                    ) : null}

                    {/* Monthly spend hero. */}
                    <div className="flex flex-col gap-1 rounded-2xl border bg-card p-5">
                        <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                            {t.insights.spentThisMonth}
                        </span>
                        <MonthlySpend spend={spend} />
                    </div>

                    {/* Actions. */}
                    <div className="flex items-center gap-2">
                        <Button
                            variant={editing ? 'default' : 'secondary'}
                            className="flex-1"
                            onClick={handleToggleEditing}
                            disabled={saving}
                        >
                            {editing ? (
                                <Check data-icon="inline-start" />
                            ) : (
                                <Pencil data-icon="inline-start" />
                            )}
                            {editing ? t.common.done : t.common.edit}
                        </Button>
                        <Button
                            variant="destructive"
                            size="icon"
                            onClick={requestDelete}
                            disabled={saving}
                            aria-label={t.common.delete}
                        >
                            <Trash2 />
                        </Button>
                    </div>

                    <EntityRecentTransactions
                        title={t.insights.lastMovements}
                        viewAllLabel={t.insights.viewAll}
                        onViewAll={viewAllTransactions}
                        transactions={recent}
                    />
                </div>
            </SheetContent>

            <Dialog open={deleteOpen} onOpenChange={setDeleteOpen}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>
                            {hasChildren
                                ? t.insights.tagDeleteWithChildrenTitle
                                : t.insights.tagDeleteTitle}
                        </DialogTitle>
                    </DialogHeader>
                    {hasChildren ? (
                        <div className="flex flex-col gap-3 text-sm">
                            <p>
                                <span className="font-medium">{tag.name}</span>{' '}
                                {t.insights.tagDeleteWithChildrenPrompt({
                                    count: childTags.length,
                                })}
                            </p>
                            <ul className="list-disc pl-5 text-muted-foreground">
                                {childTags.map((c) => (
                                    <li key={c.id}>{c.name}</li>
                                ))}
                            </ul>
                        </div>
                    ) : (
                        <p className="text-sm text-muted-foreground">
                            {t.insights.tagDeleteConfirm({ name: tag.name })}
                        </p>
                    )}
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setDeleteOpen(false)}
                            disabled={saving}
                        >
                            {t.common.cancel}
                        </Button>
                        {hasChildren ? (
                            <Button
                                variant="outline"
                                onClick={() => performDelete(false)}
                                disabled={saving}
                            >
                                {t.insights.keepSubtags}
                            </Button>
                        ) : null}
                        <Button
                            variant="destructive"
                            onClick={() => performDelete(hasChildren)}
                            disabled={saving}
                        >
                            {hasChildren
                                ? t.insights.deleteEverything
                                : t.common.delete}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </Sheet>
    )
}
