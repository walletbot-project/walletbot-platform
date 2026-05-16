import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { Pencil, Plus } from 'lucide-react'
import { useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { normalizeTagColor } from '@/lib/tag-colors'
import { TagDialog, type TagFormValue } from '@/pages/insights/tag-dialog'

type TagRow = {
    id: string
    name: string
    color?: string
    transactionCount: number
}

export function TagsView() {
    const tags = useQuery(api.tags.queries.listActiveWithCounts)
    const createTag = useMutation(api.tags.mutations.create)
    const updateTag = useMutation(api.tags.mutations.update)
    const archiveTag = useMutation(api.tags.mutations.archive)

    const [editing, setEditing] = useState<TagRow | null>(null)
    const [creating, setCreating] = useState(false)

    const handleCreate = async (value: TagFormValue) => {
        const id = `${Date.now()}${Math.random().toString(36).slice(2, 8)}`
        const promise = createTag({
            id,
            name: value.name,
            color: value.color,
        })
        toast.promise(promise, {
            loading: 'Creating tag…',
            success: 'Tag created',
            error: 'Failed to create tag',
        })
        await promise
        setCreating(false)
    }

    const handleUpdate = async (id: string, value: TagFormValue) => {
        const promise = updateTag({
            id,
            name: value.name,
            color: value.color,
        })
        toast.promise(promise, {
            loading: 'Saving tag…',
            success: 'Tag saved',
            error: 'Failed to save tag',
        })
        await promise
        setEditing(null)
    }

    const handleDelete = async (id: string) => {
        const promise = archiveTag({ id })
        toast.promise(promise, {
            loading: 'Deleting tag…',
            success: 'Tag deleted',
            error: 'Failed to delete tag',
        })
        await promise
        setEditing(null)
    }

    return (
        <div className="flex flex-1 flex-col">
            <div className="flex justify-end p-4">
                <Button size="sm" onClick={() => setCreating(true)}>
                    <Plus data-icon="inline-start" />
                    New
                </Button>
            </div>

            <div className="flex-1 px-4 pb-4">
                {tags === undefined ? (
                    <TagsSkeleton />
                ) : tags.length === 0 ? (
                    <p className="py-12 text-center text-sm text-muted-foreground">
                        No tags yet.
                    </p>
                ) : (
                    <ul className="divide-y rounded-md border bg-card">
                        {tags.map((tag) => (
                            <li
                                key={tag.id}
                                className="flex items-center justify-between gap-3 px-4 py-3 text-sm"
                            >
                                <span
                                    className="inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-medium text-foreground"
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
                onOpenChange={setCreating}
                title="New Tag"
                submitLabel="Create"
                onSubmit={handleCreate}
            />

            <TagDialog
                open={editing !== null}
                onOpenChange={(open) => {
                    if (!open) setEditing(null)
                }}
                title="Edit Tag"
                submitLabel="Save"
                initialValue={
                    editing
                        ? {
                              name: editing.name,
                              color: normalizeTagColor(editing.color),
                          }
                        : undefined
                }
                onSubmit={(value) =>
                    editing
                        ? handleUpdate(editing.id, value)
                        : Promise.resolve()
                }
                onDelete={editing ? () => handleDelete(editing.id) : undefined}
            />
        </div>
    )
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
