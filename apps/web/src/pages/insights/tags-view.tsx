import type { api } from '@wallet-bot/backend/api'
import type { FunctionReturnType } from 'convex/server'
import { StateMessage } from '@/components/m3/state-message'
import { TagChip } from '@/components/m3/tag-chip'
import { SortableList } from '@/components/sortable-list'
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
    /** Reorder mode: chips show a drag handle and stop opening on click. */
    editing: boolean
    /** One level's new order: the children of `parentId` (top level: null). */
    onReorder: (parentId: string | null, ids: string[]) => void
}

type TagNode = { tag: TagWithCount; children: TagNode[] }

/**
 * The tags list — one page of the Insights tab view. Each tag stays
 * represented by its chip, with sub-tags indented under their parent, matching
 * the native tags view. Pure list: detail and creation live in the Insights
 * screen.
 *
 * In reorder mode each level is its own sortable list, so a tag moves only
 * among its siblings and carries its sub-tags along; nothing can land above
 * its own parent (WAL-199).
 */
export function TagsView({
    tags,
    onSelect,
    editing,
    onReorder,
}: TagsViewProps) {
    const t = useT()

    if (tags === undefined) return <TagsSkeleton />
    if (tags.length === 0) {
        return <StateMessage icon="sell" title={t.insights.noTagsYet} />
    }

    return (
        <TagLevel
            className="px-3 pt-2 pb-24"
            parentId={null}
            nodes={buildTagTree(tags)}
            editing={editing}
            onSelect={onSelect}
            onReorder={onReorder}
        />
    )
}

function TagLevel({
    className,
    parentId,
    nodes,
    editing,
    onSelect,
    onReorder,
}: {
    className: string
    parentId: string | null
    nodes: TagNode[]
    editing: boolean
    onSelect: (id: string) => void
    onReorder: (parentId: string | null, ids: string[]) => void
}) {
    return (
        <SortableList
            className={className}
            gap={8}
            liftedClassName="rounded-3xl bg-surface-container-high shadow-lg outline-8 outline-surface-container-high"
            items={nodes}
            idOf={(node) => node.tag.id}
            nameOf={(node) => node.tag.name}
            editing={editing}
            onReorder={(ids) =>
                // A tag whose parent is gone shows at the top level but still
                // carries that parentId; it is not a sibling there, so it is
                // left out rather than making the whole level's write fail.
                onReorder(
                    parentId,
                    ids.filter(
                        (id) =>
                            (nodes.find((node) => node.tag.id === id)?.tag
                                .parentId ?? null) === parentId,
                    ),
                )
            }
            renderItem={(node, { dragHandle }) => (
                <div className="flex flex-col">
                    <div className="flex items-center gap-1">
                        <TagChip
                            name={node.tag.name}
                            color={normalizeTagColor(node.tag.color)}
                            // While reordering, chips only move.
                            onClick={
                                editing
                                    ? undefined
                                    : () => onSelect(node.tag.id)
                            }
                            trailing={
                                <span className="tabular-nums opacity-70">
                                    {node.tag.transactionCount}
                                </span>
                            }
                        />
                        {dragHandle}
                    </div>
                    {node.children.length > 0 ? (
                        <TagLevel
                            className="pt-2 pl-5"
                            parentId={node.tag.id}
                            nodes={node.children}
                            editing={editing}
                            onSelect={onSelect}
                            onReorder={onReorder}
                        />
                    ) : null}
                </div>
            )}
        />
    )
}

/**
 * Groups `tags` into their tree, keeping the query's order inside each level
 * (the user's order, then name). A tag whose parent is missing shows at the
 * top level.
 */
function buildTagTree(tags: TagWithCount[]): TagNode[] {
    const nodes = new Map<string, TagNode>(
        tags.map((tag) => [tag.id, { tag, children: [] }]),
    )
    const roots: TagNode[] = []
    for (const tag of tags) {
        const node = nodes.get(tag.id)
        if (!node) continue
        const parent = tag.parentId ? nodes.get(tag.parentId) : undefined
        if (parent) parent.children.push(node)
        else roots.push(node)
    }
    return roots
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
