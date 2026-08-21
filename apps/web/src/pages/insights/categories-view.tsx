import type { api } from '@wallet-bot/backend/api'
import type { FunctionReturnType } from 'convex/server'
import { CategoryIcon } from '@/components/category-icon'
import { EntityAvatar, EntityListTile } from '@/components/m3/entity-list-tile'
import { StateMessage } from '@/components/m3/state-message'
import { Skeleton } from '@/components/ui/skeleton'
import { CATEGORY_DEFAULT_COLOR, normalizeColor } from '@/lib/entity-colors'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { useT } from '@/lib/i18n'

type CategoryWithCount = FunctionReturnType<
    typeof api.v1.categories.queries.listActiveWithCounts
>[number]

type CategoriesViewProps = {
    /** `undefined` while loading. */
    categories: CategoryWithCount[] | undefined
    onSelect: (id: string) => void
}

/**
 * The categories list — one page of the Insights tab view. Pure list: the
 * detail and creation presentation live in the Insights screen, so the shared
 * pane can sit outside the tab pages.
 */
export function CategoriesView({ categories, onSelect }: CategoriesViewProps) {
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
        <div
            className="flex flex-col px-4 pt-4 pb-24"
            style={{ gap: GROUP_SPACING }}
        >
            {categories.map((category, index) => {
                const accent = normalizeColor(
                    category.color,
                    CATEGORY_DEFAULT_COLOR,
                )
                return (
                    <EntityListTile
                        key={category.id}
                        radius={groupedRadius(index, categories.length)}
                        onClick={() => onSelect(category.id)}
                        chevron
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
            })}
        </div>
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
