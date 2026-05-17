import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { Pencil, Plus } from 'lucide-react'
import { useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import {
    CategoryDialog,
    type CategoryFormValue,
} from '@/pages/insights/category-dialog'

type CategoryRow = {
    id: string
    name: string
    transactionCount: number
}

export function CategoriesView() {
    const categories = useQuery(api.categories.queries.listActiveWithCounts)
    const createCategory = useMutation(api.categories.mutations.create)
    const updateCategory = useMutation(api.categories.mutations.update)
    const archiveCategory = useMutation(api.categories.mutations.archive)

    const [editing, setEditing] = useState<CategoryRow | null>(null)
    const [creating, setCreating] = useState(false)

    const handleCreate = async (value: CategoryFormValue) => {
        const id = `${Date.now()}${Math.random().toString(36).slice(2, 8)}`
        const promise = createCategory({ id, name: value.name })
        toast.promise(promise, {
            loading: 'Creating category…',
            success: 'Category created',
            error: 'Failed to create category',
        })
        await promise
        setCreating(false)
    }

    const handleUpdate = async (id: string, value: CategoryFormValue) => {
        const promise = updateCategory({ id, name: value.name })
        toast.promise(promise, {
            loading: 'Saving category…',
            success: 'Category saved',
            error: 'Failed to save category',
        })
        await promise
        setEditing(null)
    }

    const handleDelete = async (id: string) => {
        const promise = archiveCategory({ id })
        toast.promise(promise, {
            loading: 'Deleting category…',
            success: 'Category deleted',
            error: 'Failed to delete category',
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
                {categories === undefined ? (
                    <CategoriesSkeleton />
                ) : categories.length === 0 ? (
                    <p className="py-12 text-center text-sm text-muted-foreground">
                        No categories yet.
                    </p>
                ) : (
                    <ul className="divide-y rounded-md border bg-card">
                        {categories.map((category) => (
                            <li
                                key={category.id}
                                className="flex items-center justify-between gap-3 px-4 py-3 text-sm"
                            >
                                <span className="font-medium">
                                    {category.name}
                                </span>
                                <div className="flex items-center gap-3">
                                    <span className="text-sm tabular-nums text-muted-foreground">
                                        {category.transactionCount}
                                    </span>
                                    <Button
                                        type="button"
                                        variant="ghost"
                                        size="icon-sm"
                                        onClick={() => setEditing(category)}
                                        aria-label={`Edit ${category.name}`}
                                    >
                                        <Pencil />
                                    </Button>
                                </div>
                            </li>
                        ))}
                    </ul>
                )}
            </div>

            <CategoryDialog
                open={creating}
                onOpenChange={setCreating}
                title="New Category"
                submitLabel="Create"
                onSubmit={handleCreate}
            />

            <CategoryDialog
                open={editing !== null}
                onOpenChange={(open) => {
                    if (!open) setEditing(null)
                }}
                title="Edit Category"
                submitLabel="Save"
                initialValue={editing ? { name: editing.name } : undefined}
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

function CategoriesSkeleton() {
    return (
        <div className="space-y-2">
            {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-12 w-full" />
            ))}
        </div>
    )
}
