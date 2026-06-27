import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { useMemo, useState } from 'react'
import { toast } from 'sonner'
import { Skeleton } from '@/components/ui/skeleton'
import { normalizeTagColor } from '@/lib/tag-colors'
import {
    TagDetailsSheet,
    type TagSummary,
} from '@/pages/insights/tag-details-sheet'
import {
    TagDialog,
    type TagFormValue,
    type TagOption,
} from '@/pages/insights/tag-dialog'

function newId() {
    return `${Date.now()}${Math.random().toString(36).slice(2, 8)}`
}

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

    const [selectedId, setSelectedId] = useState<string | null>(null)

    const tagList = useMemo(() => tags ?? [], [tags])
    const orderedTagTree = useMemo(() => buildTagTree(tagList), [tagList])

    // Derive the open tag from the live query so edits saved in the sheet are
    // reflected immediately (a stored snapshot would go stale on save).
    const selected: TagSummary | null = useMemo(() => {
        if (selectedId === null) return null
        const tag = tagList.find((t) => t.id === selectedId)
        return tag
            ? {
                  id: tag.id,
                  name: tag.name,
                  color: tag.color,
                  parentId: tag.parentId,
              }
            : null
    }, [tagList, selectedId])

    const parentOptions: TagOption[] = useMemo(
        () =>
            tagList.map((t) => ({
                id: t.id,
                name: t.name,
                color: t.color,
                parentId: t.parentId,
            })),
        [tagList],
    )

    const selectedChildren = useMemo(
        () =>
            selected
                ? tagList
                      .filter((t) => t.parentId === selected.id)
                      .map((t) => ({
                          id: t.id,
                          name: t.name,
                          color: t.color,
                          parentId: t.parentId,
                      }))
                : [],
        [tagList, selected],
    )

    const handleCreate = async (value: TagFormValue) => {
        const promise = createTag({
            id: newId(),
            name: value.name,
            color: value.color,
            parentId: value.parentId ?? undefined,
        })
        toast.promise(promise, {
            loading: 'Creando tag…',
            success: 'Tag creado',
            error: 'No se pudo crear el tag',
        })
        await promise
        onCreatingChange(false)
    }

    return (
        <div className="flex flex-1 flex-col">
            <div className="flex-1 p-4">
                {tags === undefined ? (
                    <TagsSkeleton />
                ) : tags.length === 0 ? (
                    <p className="py-12 text-center text-sm text-muted-foreground">
                        No tenés tags aún.
                    </p>
                ) : (
                    <ul className="flex flex-col gap-1.5">
                        {orderedTagTree.map(({ tag, depth }) => (
                            <li
                                key={tag.id}
                                style={{ paddingLeft: `${depth * 20}px` }}
                            >
                                <button
                                    type="button"
                                    onClick={() => setSelectedId(tag.id)}
                                    className="inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-xs font-medium text-foreground transition-transform hover:scale-[1.02]"
                                    style={{
                                        backgroundColor: normalizeTagColor(
                                            tag.color,
                                        ),
                                    }}
                                >
                                    <span className="size-2 rounded-full bg-white/70" />
                                    {tag.name}
                                    <span className="tabular-nums opacity-70">
                                        {tag.transactionCount}
                                    </span>
                                </button>
                            </li>
                        ))}
                    </ul>
                )}
            </div>

            <TagDialog
                open={creating}
                onOpenChange={onCreatingChange}
                title="Nuevo tag"
                submitLabel="Crear"
                parentOptions={parentOptions}
                onSubmit={handleCreate}
            />

            <TagDetailsSheet
                tag={selected}
                childTags={selectedChildren}
                open={selectedId !== null}
                onOpenChange={(open) => {
                    if (!open) setSelectedId(null)
                }}
            />
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
        <div className="flex flex-wrap gap-2">
            {Array.from({ length: 6 }).map((_, i) => (
                <Skeleton key={i} className="h-7 w-24 rounded-full" />
            ))}
        </div>
    )
}
