import type { api } from '@wallet-bot/backend/api'
import type { FunctionReturnType } from 'convex/server'
import { StateMessage } from '@/components/m3/state-message'
import { TagChip } from '@/components/m3/tag-chip'
import { Skeleton } from '@/components/ui/skeleton'
import { useT } from '@/lib/i18n'
import { normalizeTagColor } from '@/lib/tag-colors'

type TagWithCount = FunctionReturnType<
    typeof api.v1.tags.queries.listActiveWithCounts
>[number]

type TagsViewProps = {
    /** `undefined` while loading. */
    tags: TagWithCount[] | undefined
    onSelect: (id: string) => void
}

/**
 * The tags list — one page of the Insights tab view. Each tag stays
 * represented by its chip, with sub-tags indented under their parent, matching
 * the native tags view. Pure list: detail and creation live in the Insights
 * screen.
 */
export function TagsView({ tags, onSelect }: TagsViewProps) {
    const t = useT()

    if (tags === undefined) return <TagsSkeleton />
    if (tags.length === 0) {
        return <StateMessage icon="sell" title={t.insights.noTagsYet} />
    }

    return (
        <ul className="flex flex-col gap-2 px-3 pt-2 pb-24">
            {buildTagTree(tags).map(({ tag, depth }) => (
                <li
                    key={tag.id}
                    className="flex"
                    style={{ paddingLeft: depth * 20 }}
                >
                    <TagChip
                        name={tag.name}
                        color={normalizeTagColor(tag.color)}
                        onClick={() => onSelect(tag.id)}
                        trailing={
                            <span className="tabular-nums opacity-70">
                                {tag.transactionCount}
                            </span>
                        }
                    />
                </li>
            ))}
        </ul>
    )
}

function buildTagTree(tags: TagWithCount[]): {
    tag: TagWithCount
    depth: number
}[] {
    const tagsById = new Map(tags.map((tag) => [tag.id, tag]))
    const childrenByParent = new Map<string, TagWithCount[]>()
    const roots: TagWithCount[] = []

    for (const tag of tags) {
        if (tag.parentId && tagsById.has(tag.parentId)) {
            const list = childrenByParent.get(tag.parentId) ?? []
            list.push(tag)
            childrenByParent.set(tag.parentId, list)
        } else {
            roots.push(tag)
        }
    }

    const result: { tag: TagWithCount; depth: number }[] = []
    const visit = (tag: TagWithCount, depth: number) => {
        result.push({ tag, depth })
        for (const child of childrenByParent.get(tag.id) ?? []) {
            visit(child, depth + 1)
        }
    }
    for (const root of roots) visit(root, 0)
    return result
}

function TagsSkeleton() {
    return (
        <div className="flex flex-wrap gap-2 px-3 pt-2">
            {Array.from({ length: 6 }).map((_, i) => (
                <Skeleton key={i} className="h-8 w-24 rounded-lg" />
            ))}
        </div>
    )
}
