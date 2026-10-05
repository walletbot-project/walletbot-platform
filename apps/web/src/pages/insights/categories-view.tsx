import type { api } from '@wallet-bot/backend/api'
import type { FunctionReturnType } from 'convex/server'
import { CategoryIcon } from '@/components/category-icon'
import { EntityAvatar, EntityListTile } from '@/components/m3/entity-list-tile'
import { StateMessage } from '@/components/m3/state-message'
import { SortableList } from '@/components/sortable-list'
import { Skeleton } from '@/components/ui/skeleton'
import { CATEGORY_DEFAULT_COLOR, normalizeColor } from '@/lib/entity-colors'
import { useT } from '@/lib/i18n'

type CategoryWithCount = FunctionReturnType<
    typeof api.v1.categories.queries.listActiveWithCounts
>[number]

type CategoriesViewProps = {
    /** `undefined` while loading. */
    categories: CategoryWithCount[] | undefined
    onSelect: (id: string) => void
    /** Reorder mode: rows show a drag handle and stop opening on click. */
    editing: boolean
    onReorder: (ids: string[]) => void
}

/**
 * The categories list — one page of the Insights tab view. Pure list: the
 * detail and creation presentation live in the Insights screen, so the shared
 * pane can sit outside the tab pages.
 */
export function CategoriesView({
    categories,
    onSelect,
    editing,
    onReorder,
}: CategoriesViewProps) {
    const t = useT()

    if (categories === undefined) return <CategoriesSkeleton />
    if (categories.length === 0) {
        return (
            <StateMessage
                icon="category"
                title={t.insights.noCategoriesYet}
                detail={t.insights.categoryNamePlaceholder}
            />
        )
    }

    return (
        <SortableList
            className="px-4 pt-4 pb-24"
            items={categories}
            idOf={(category) => category.id}
            nameOf={(category) => category.name}
            editing={editing}
            onReorder={onReorder}
            renderItem={(category, { radius, dragHandle }) => {
                const accent = normalizeColor(
                    category.color,
                    CATEGORY_DEFAULT_COLOR,
                )
                return (
                    <EntityListTile
                        radius={radius}
                        // While reordering, rows only move; the handle
                        // takes the chevron's place.
                        onClick={
                            editing ? undefined : () => onSelect(category.id)
                        }
                        chevron={!editing}
                        dragHandle={dragHandle}
                        leading={
                            <EntityAvatar color={accent}>
                                <CategoryIcon
                                    name={category.icon}
                                    size={22}
                                    color={accent}
                                />
                            </EntityAvatar>
                        }
                        title={category.name}
                        subtitle={t.insights.movementCount({
                            count: category.transactionCount,
                        })}
                    />
                )
            }}
        />
    )
}

function CategoriesSkeleton() {
    return (
        <div className="flex flex-col gap-group-seam px-4 pt-4">
            {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-18 w-full rounded-lg" />
            ))}
        </div>
    )
}
