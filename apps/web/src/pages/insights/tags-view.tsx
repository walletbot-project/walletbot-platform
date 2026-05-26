import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { Pencil } from 'lucide-react'
import { useMemo, useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import {
    Dialog,
    DialogContent,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import { Skeleton } from '@/components/ui/skeleton'
import { normalizeTagColor } from '@/lib/tag-colors'
import {
    TagDialog,
    type TagFormValue,
    type TagOption,
} from '@/pages/insights/tag-dialog'

type TagRow = {
    id: string
    name: string
    color?: string
    parentId?: string
    transactionCount: number
}

type TagsViewProps = {
    creating: boolean
    onCreatingChange: (open: boolean) => void
}

export function TagsView({ creating, onCreatingChange }: TagsViewProps) {
    const tags = useQuery(api.tags.queries.listActiveWithCounts)
    const createTag = useMutation(api.tags.mutations.create)
    const updateTag = useMutation(api.tags.mutations.update)
    const archiveTag = useMutation(api.tags.mutations.archive)

    const [editing, setEditing] = useState<TagRow | null>(null)
    const [deleteTarget, setDeleteTarget] = useState<{
        tag: TagRow
        children: TagRow[]
    } | null>(null)
    const [deleting, setDeleting] = useState(false)

    const tagList = useMemo(() => tags ?? [], [tags])

    const orderedTagTree = useMemo(() => buildTagTree(tagList), [tagList])

    const parentOptionsForCreate: TagOption[] = useMemo(
        () =>
            tagList.map((t) => ({
                id: t.id,
                name: t.name,
                color: t.color,
                parentId: t.parentId,
            })),
        [tagList],
    )

    const parentOptionsForEdit: TagOption[] = useMemo(() => {
        if (!editing) return []
        const descendants = new Set<string>()
        const queue: string[] = [editing.id]
        while (queue.length > 0) {
            const id = queue.shift() as string
            for (const t of tagList) {
                if (t.parentId === id && !descendants.has(t.id)) {
                    descendants.add(t.id)
                    queue.push(t.id)
                }
            }
        }
        return tagList
            .filter((t) => t.id !== editing.id && !descendants.has(t.id))
            .map((t) => ({
                id: t.id,
                name: t.name,
                color: t.color,
                parentId: t.parentId,
            }))
    }, [tagList, editing])

    const handleCreate = async (value: TagFormValue) => {
        const id = `${Date.now()}${Math.random().toString(36).slice(2, 8)}`
        const promise = createTag({
            id,
            name: value.name,
            color: value.color,
            parentId: value.parentId ?? undefined,
        })
        toast.promise(promise, {
            loading: 'Creating tag…',
            success: 'Tag created',
            error: 'Failed to create tag',
        })
        await promise
        onCreatingChange(false)
    }

    const handleUpdate = async (id: string, value: TagFormValue) => {
        const promise = updateTag({
            id,
            name: value.name,
            color: value.color,
            parentId: value.parentId === null ? null : value.parentId,
        })
        toast.promise(promise, {
            loading: 'Saving tag…',
            success: 'Tag saved',
            error: 'Failed to save tag',
        })
        await promise
        setEditing(null)
    }

    const requestDelete = async (tag: TagRow) => {
        const children = tagList.filter((t) => t.parentId === tag.id)
        if (children.length === 0) {
            await performDelete(tag, false)
            return
        }
        setDeleteTarget({ tag, children })
    }

    const performDelete = async (tag: TagRow, cascade: boolean) => {
        setDeleting(true)
        const promise = archiveTag({ id: tag.id, cascade })
        toast.promise(promise, {
            loading: 'Deleting tag…',
            success: 'Tag deleted',
            error: 'Failed to delete tag',
        })
        try {
            await promise
            setEditing(null)
            setDeleteTarget(null)
        } finally {
            setDeleting(false)
        }
    }

    return (
        <div className="flex flex-1 flex-col">
            <div className="flex-1 p-4">
                {tags === undefined ? (
                    <TagsSkeleton />
                ) : tags.length === 0 ? (
                    <p className="py-12 text-center text-sm text-muted-foreground">
                        No tags yet.
                    </p>
                ) : (
                    <ul className="divide-y rounded-md border bg-card">
                        {orderedTagTree.map(({ tag, depth }) => (
                            <li
                                key={tag.id}
                                className="flex items-center justify-between gap-3 py-3 pr-4 text-sm"
                                style={{
                                    paddingLeft: `${16 + depth * 20}px`,
                                }}
                            >
                                <span
                                    className="inline-flex items-center gap-2 self-start rounded-full px-3 py-1 text-xs font-medium text-foreground"
                                    style={{
                                        backgroundColor: normalizeTagColor(
                                            tag.color,
                                        ),
                                    }}
                                >
                                    <span className="size-2 rounded-full bg-white/70" />
                                    {tag.name}
                                </span>
                                <div className="flex items-center gap-3">
                                    <span className="text-sm tabular-nums text-muted-foreground">
                                        {tag.transactionCount}
                                    </span>
                                    <Button
                                        type="button"
                                        variant="ghost"
                                        size="icon-sm"
                                        onClick={() => setEditing(tag)}
                                        aria-label={`Edit ${tag.name}`}
                                    >
                                        <Pencil />
                                    </Button>
                                </div>
                            </li>
                        ))}
                    </ul>
                )}
            </div>

            <TagDialog
                open={creating}
                onOpenChange={onCreatingChange}
                title="New Tag"
                submitLabel="Create"
                parentOptions={parentOptionsForCreate}
                onSubmit={handleCreate}
            />

            <TagDialog
                open={editing !== null}
                onOpenChange={(open) => {
                    if (!open) setEditing(null)
                }}
                title="Edit Tag"
                submitLabel="Save"
                parentOptions={parentOptionsForEdit}
                initialValue={
                    editing
                        ? {
                              name: editing.name,
                              color: normalizeTagColor(editing.color),
                              parentId: editing.parentId ?? null,
                          }
                        : undefined
                }
                onSubmit={(value) =>
                    editing
                        ? handleUpdate(editing.id, value)
                        : Promise.resolve()
                }
                onDelete={editing ? () => requestDelete(editing) : undefined}
            />

            <Dialog
                open={deleteTarget !== null}
                onOpenChange={(open) => {
                    if (!open && !deleting) setDeleteTarget(null)
                }}
            >
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Delete tag with sub-tags</DialogTitle>
                    </DialogHeader>
                    {deleteTarget ? (
                        <div className="flex flex-col gap-3 text-sm">
                            <p>
                                <span className="font-medium">
                                    {deleteTarget.tag.name}
                                </span>{' '}
                                has {deleteTarget.children.length} sub-tag
                                {deleteTarget.children.length === 1 ? '' : 's'}.
                                Do you want to delete the sub-tags too?
                            </p>
                            <ul className="list-disc pl-5 text-muted-foreground">
                                {deleteTarget.children.map((c) => (
                                    <li key={c.id}>{c.name}</li>
                                ))}
                            </ul>
                        </div>
                    ) : null}
                    <DialogFooter>
                        <Button
                            type="button"
                            variant="outline"
                            onClick={() => setDeleteTarget(null)}
                            disabled={deleting}
                        >
                            Cancel
                        </Button>
                        <Button
                            type="button"
                            variant="outline"
                            onClick={() =>
                                deleteTarget &&
                                performDelete(deleteTarget.tag, false)
                            }
                            disabled={deleting}
                        >
                            Keep sub-tags
                        </Button>
                        <Button
                            type="button"
                            variant="destructive"
                            onClick={() =>
                                deleteTarget &&
                                performDelete(deleteTarget.tag, true)
                            }
                            disabled={deleting}
                        >
                            Delete all
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </div>
    )
}

function buildTagTree(tags: TagRow[]): { tag: TagRow; depth: number }[] {
    const tagsById = new Map(tags.map((t) => [t.id, t]))
    const childrenByParent = new Map<string, TagRow[]>()
    const roots: TagRow[] = []

    for (const tag of tags) {
        if (tag.parentId && tagsById.has(tag.parentId)) {
            const list = childrenByParent.get(tag.parentId) ?? []
            list.push(tag)
            childrenByParent.set(tag.parentId, list)
        } else {
            roots.push(tag)
        }
    }

    const result: { tag: TagRow; depth: number }[] = []
    const visit = (tag: TagRow, depth: number) => {
        result.push({ tag, depth })
        const children = childrenByParent.get(tag.id) ?? []
        for (const child of children) visit(child, depth + 1)
    }
    for (const root of roots) visit(root, 0)
    return result
}

function TagsSkeleton() {
    return (
        <div className="space-y-2">
            {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-12 w-full" />
            ))}
        </div>
    )
}
