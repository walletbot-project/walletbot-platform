import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { useMemo, useState } from 'react'
import { toast } from 'sonner'
import { CategoryIcon } from '@/components/category-icon'
import { Skeleton } from '@/components/ui/skeleton'
import { CATEGORY_DEFAULT_COLOR, normalizeColor } from '@/lib/entity-colors'
import { useT } from '@/lib/i18n'
import {
    CategoryDetailsSheet,
    type CategorySummary,
} from '@/pages/insights/category-details-sheet'
import {
    CategoryDialog,
    type CategoryFormValue,
} from '@/pages/insights/category-dialog'

function newId() {
    return `${Date.now()}${Math.random().toString(36).slice(2, 8)}`
}

type CategoriesViewProps = {
    creating: boolean
    onCreatingChange: (open: boolean) => void
}

export function CategoriesView({
    creating,
    onCreatingChange,
}: CategoriesViewProps) {
    const t = useT()
    const categories = useQuery(api.v1.categories.queries.listActiveWithCounts)
    const createCategory = useMutation(api.v1.categories.mutations.create)

    const [selectedId, setSelectedId] = useState<string | null>(null)

    // Derive the open category from the live query so edits saved in the sheet
    // are reflected immediately (a stored snapshot would go stale on save).
    const selected: CategorySummary | null = useMemo(() => {
        if (selectedId === null || categories === undefined) return null
        const category = categories.find((c) => c.id === selectedId)
        return category
            ? {
                  id: category.id,
                  name: category.name,
                  icon: category.icon,
                  color: category.color,
                  description: category.description,
              }
            : null
    }, [categories, selectedId])

    const handleCreate = async (value: CategoryFormValue) => {
        const promise = createCategory({
            id: newId(),
            name: value.name,
            description: value.description || undefined,
            color: value.color,
            icon: value.icon,
        })
        toast.promise(promise, {
            loading: t.insights.categoryCreating,
            success: t.insights.categoryCreated,
            error: t.insights.categoryCreateFailed,
        })
        await promise
        onCreatingChange(false)
    }

    return (
        <div className="flex flex-1 flex-col">
            <div className="flex-1 p-4">
                {categories === undefined ? (
                    <CategoriesSkeleton />
                ) : categories.length === 0 ? (
                    <p className="py-12 text-center text-sm text-muted-foreground">
                        {t.insights.noCategoriesYet}
                    </p>
                ) : (
                    <ul className="divide-y overflow-hidden rounded-md border bg-card">
                        {categories.map((category) => {
                            const accent = normalizeColor(
                                category.color,
                                CATEGORY_DEFAULT_COLOR,
                            )
                            return (
                                <li key={category.id}>
                                    <button
                                        type="button"
                                        onClick={() =>
                                            setSelectedId(category.id)
                                        }
                                        className="flex w-full items-center gap-4 px-4 py-3 text-left transition-colors hover:bg-accent/50"
                                    >
                                        <span
                                            className="flex size-10 shrink-0 items-center justify-center rounded-full"
                                            style={{
                                                backgroundColor: `${accent}2E`,
                                            }}
                                        >
                                            <CategoryIcon
                                                name={category.icon}
                                                className="size-5"
                                                color={accent}
                                            />
                                        </span>
                                        <span className="min-w-0 flex-1 truncate text-sm font-medium">
                                            {category.name}
                                        </span>
                                        <span className="shrink-0 text-sm tabular-nums text-muted-foreground">
                                            {category.transactionCount}
                                        </span>
                                    </button>
                                </li>
                            )
                        })}
                    </ul>
                )}
            </div>

            <CategoryDialog
                open={creating}
                onOpenChange={onCreatingChange}
                onSubmit={handleCreate}
            />

            <CategoryDetailsSheet
                category={selected}
                open={selectedId !== null}
                onOpenChange={(open) => {
                    if (!open) setSelectedId(null)
                }}
            />
        </div>
    )
}

function CategoriesSkeleton() {
    return (
        <div className="space-y-2">
            {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-14 w-full" />
            ))}
        </div>
    )
}
