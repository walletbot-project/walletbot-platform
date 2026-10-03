import { api } from '@wallet-bot/backend/api'
import {
    compareByPosition,
    compareByPositionThenName,
} from '@wallet-bot/shared'
import { IconButton, TabItem, Tabs } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { DetailNotFound, DetailSkeleton } from '@/components/detail-fallbacks'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { ListDetailLayout } from '@/components/m3/list-detail-layout'
import { useOccurrenceCutoff } from '@/hooks/use-occurrence-cutoff'
import { useT } from '@/lib/i18n'
import { newId } from '@/lib/new-id'
import { applyReorder } from '@/lib/ordering'
import { CategoriesView } from '@/pages/insights/categories-view'
import {
    CategoryDetail,
    type CategorySummary,
} from '@/pages/insights/category-detail'
import {
    CategoryForm,
    type CategoryFormValue,
} from '@/pages/insights/category-form'
import { TagDetail, type TagSummary } from '@/pages/insights/tag-detail'
import {
    TagForm,
    type TagFormValue,
    type TagOption,
} from '@/pages/insights/tag-form'
import { TagsView } from '@/pages/insights/tags-view'

type InsightsTab = 'categories' | 'tags'

/** The tab is a path segment, so a reload or a shared link lands where it left. */
function useInsightsTab(): InsightsTab {
    const { tab } = useParams()
    return tab === 'tags' ? 'tags' : 'categories'
}

/**
 * Insights: the Categories/Tags tabs over one shared detail pane.
 *
 * Both the visible tab and whatever is open beside it are path segments —
 * `/insights/categories`, `/insights/tags/new`, `/insights/tags/:id` — so no
 * part of this screen's shape lives in React state.
 */
export function Insights() {
    const t = useT()
    const navigate = useNavigate()
    const tab = useInsightsTab()

    const asOfMs = useOccurrenceCutoff()
    const categories = useQuery(
        api.v1.categories.queries.listActiveWithCounts,
        { asOfMs },
    )
    const tags = useQuery(api.v1.tags.queries.listActiveWithCounts, { asOfMs })
    // Reorder mode for the visible tab, like the home dashboard's edit mode:
    // a mode of the list, not something open beside it, so it stays out of
    // the URL.
    const [editingTab, setEditingTab] = useState<InsightsTab | null>(null)
    const editing = editingTab === tab
    // Optimistic, so a dropped row stays where it landed; Convex rolls the
    // patch back by itself if the mutation fails.
    const reorderCategories = useMutation(
        api.v1.categories.mutations.reorder,
    ).withOptimisticUpdate((localStore, args) => {
        for (const { args: queryArgs, value } of localStore.getAllQueries(
            api.v1.categories.queries.listActiveWithCounts,
        )) {
            if (!value) continue
            localStore.setQuery(
                api.v1.categories.queries.listActiveWithCounts,
                queryArgs,
                applyReorder(value, args.ids, compareByPosition),
            )
        }
        const active = localStore.getQuery(
            api.v1.categories.queries.listActive,
            {},
        )
        if (active) {
            localStore.setQuery(
                api.v1.categories.queries.listActive,
                {},
                applyReorder(active, args.ids, compareByPosition),
            )
        }
    })
    // Tags keep their tree: only one level changes, and the flat
    // `listActive` stays alphabetical, so only the tree query is patched.
    const reorderTags = useMutation(
        api.v1.tags.mutations.reorder,
    ).withOptimisticUpdate((localStore, args) => {
        for (const { args: queryArgs, value } of localStore.getAllQueries(
            api.v1.tags.queries.listActiveWithCounts,
        )) {
            if (!value) continue
            localStore.setQuery(
                api.v1.tags.queries.listActiveWithCounts,
                queryArgs,
                applyReorder(value, args.ids, compareByPositionThenName),
            )
        }
    })
    const canReorder =
        ((tab === 'categories' ? categories : tags)?.length ?? 0) > 1

    const list = (
        <>
            <AppBar
                title={t.nav.insights}
                actions={
                    editing ? (
                        <IconButton
                            aria-label={t.common.done}
                            onPress={() => setEditingTab(null)}
                            className="text-on-surface-variant"
                        >
                            <Icon name="check" />
                        </IconButton>
                    ) : (
                        <>
                            {canReorder ? (
                                <IconButton
                                    aria-label={
                                        tab === 'categories'
                                            ? t.reorder.reorderCategories
                                            : t.reorder.reorderTags
                                    }
                                    onPress={() => setEditingTab(tab)}
                                    className="text-on-surface-variant"
                                >
                                    <Icon name="edit" />
                                </IconButton>
                            ) : null}
                            <IconButton
                                aria-label={
                                    tab === 'categories'
                                        ? t.insights.newCategory
                                        : t.insights.newTag
                                }
                                onPress={() => navigate(`/insights/${tab}/new`)}
                                className="text-on-surface-variant"
                            >
                                <Icon name="add" />
                            </IconButton>
                        </>
                    )
                }
            />
            <Tabs
                aria-label={t.nav.insights}
                selectedKey={tab}
                onSelectionChange={(key) => {
                    // Leaving the tab ends reorder mode.
                    setEditingTab(null)
                    navigate(`/insights/${key}`)
                }}
                className="m3-tabs flex min-h-0 flex-1 flex-col"
                contentClassName="min-h-0 flex-1 overflow-y-auto"
            >
                {/*
                 * The label is wrapped so `m3-tabs` can hang the active
                 * indicator off it: Material's primary tab indicator is as
                 * wide as the label, not as wide as the tab. `textValue` keeps
                 * the collection's plain-text name now that `title` is an
                 * element.
                 */}
                <TabItem
                    key="categories"
                    textValue={t.insights.categories}
                    title={
                        <span className="m3-tab-label">
                            {t.insights.categories}
                        </span>
                    }
                >
                    <CategoriesView
                        categories={categories}
                        onSelect={(id) =>
                            navigate(`/insights/categories/${id}`)
                        }
                        editing={editing}
                        onReorder={(ids) => {
                            reorderCategories({ ids }).catch(() =>
                                toast.error(t.reorder.categoriesFailed),
                            )
                        }}
                    />
                </TabItem>
                <TabItem
                    key="tags"
                    textValue={t.insights.tags}
                    title={
                        <span className="m3-tab-label">{t.insights.tags}</span>
                    }
                >
                    <TagsView
                        tags={tags}
                        onSelect={(id) => navigate(`/insights/tags/${id}`)}
                        editing={editing}
                        onReorder={(parentId, ids) => {
                            reorderTags({
                                ...(parentId ? { parentId } : {}),
                                ids,
                            }).catch(() => toast.error(t.reorder.tagsFailed))
                        }}
                    />
                </TabItem>
            </Tabs>
        </>
    )

    return (
        <ListDetailLayout
            list={list}
            closeTo={`/insights/${tab}`}
            detailTitle={
                tab === 'categories'
                    ? t.insights.categoryDetails
                    : t.insights.tagDetails
            }
            placeholder={
                <div className="flex flex-1 items-center justify-center p-8">
                    <p className="m3-body-large max-w-xs text-center text-on-surface-variant">
                        {tab === 'categories'
                            ? t.insights.selectCategoryDetail
                            : t.insights.selectTagDetail}
                    </p>
                </div>
            }
        />
    )
}

/** `/insights/:tab/new` — the create form for whichever tab is showing. */
export function InsightCreateRoute() {
    const t = useT()
    const navigate = useNavigate()
    const tab = useInsightsTab()
    // Only the tag form needs the tag list (for the parent picker).
    const asOfMs = useOccurrenceCutoff()
    const tags = useQuery(
        api.v1.tags.queries.listActiveWithCounts,
        tab === 'tags' ? { asOfMs } : 'skip',
    )
    const createCategory = useMutation(api.v1.categories.mutations.create)
    const createTag = useMutation(api.v1.tags.mutations.create)

    const close = () => navigate(`/insights/${tab}`)

    const parentOptions: TagOption[] = useMemo(
        () =>
            (tags ?? []).map((item) => ({
                id: item.id,
                name: item.name,
                color: item.color,
                parentId: item.parentId,
            })),
        [tags],
    )

    const handleCreateCategory = async (value: CategoryFormValue) => {
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
        // The toast already reported the failure; swallowing it here keeps the
        // form open without an unhandled rejection.
        try {
            await promise
        } catch {
            return
        }
        close()
    }

    const handleCreateTag = async (value: TagFormValue) => {
        const promise = createTag({
            id: newId(),
            name: value.name,
            color: value.color,
            parentId: value.parentId ?? undefined,
        })
        toast.promise(promise, {
            loading: t.insights.tagCreating,
            success: t.insights.tagCreated,
            error: t.insights.tagCreateFailed,
        })
        try {
            await promise
        } catch {
            return
        }
        close()
    }

    if (tab === 'categories') {
        return <CategoryForm onClose={close} onSubmit={handleCreateCategory} />
    }

    return (
        <TagForm
            title={t.insights.newTag}
            submitLabel={t.common.create}
            parentOptions={parentOptions}
            onClose={close}
            onSubmit={handleCreateTag}
        />
    )
}

/** `/insights/:tab/:entityId` — one category's or tag's detail. */
export function InsightDetailRoute() {
    const navigate = useNavigate()
    const tab = useInsightsTab()
    const { entityId } = useParams()
    // Each tab reads only its own list.
    const asOfMs = useOccurrenceCutoff()
    const categories = useQuery(
        api.v1.categories.queries.listActiveWithCounts,
        tab === 'categories' ? { asOfMs } : 'skip',
    )
    const tags = useQuery(
        api.v1.tags.queries.listActiveWithCounts,
        tab === 'tags' ? { asOfMs } : 'skip',
    )

    const close = () => navigate(`/insights/${tab}`)
    const loading =
        tab === 'categories' ? categories === undefined : tags === undefined

    // Derived from the live query so an edit saved here shows up immediately
    // instead of going stale against a snapshot.
    const category: CategorySummary | null = useMemo(() => {
        if (tab !== 'categories' || categories === undefined) return null
        const match = categories.find((c) => c.id === entityId)
        return match
            ? {
                  id: match.id,
                  name: match.name,
                  icon: match.icon,
                  color: match.color,
                  description: match.description,
              }
            : null
    }, [tab, categories, entityId])

    const tag: TagSummary | null = useMemo(() => {
        if (tab !== 'tags' || tags === undefined) return null
        const match = tags.find((item) => item.id === entityId)
        return match
            ? {
                  id: match.id,
                  name: match.name,
                  color: match.color,
                  parentId: match.parentId,
              }
            : null
    }, [tab, tags, entityId])

    const childTags = useMemo(
        () =>
            tag
                ? (tags ?? [])
                      .filter((item) => item.parentId === tag.id)
                      .map((item) => ({
                          id: item.id,
                          name: item.name,
                          color: item.color,
                          parentId: item.parentId,
                      }))
                : [],
        [tags, tag],
    )

    if (loading) return <DetailSkeleton />

    if (category !== null) {
        return <CategoryDetail category={category} onClose={close} />
    }
    if (tag !== null) {
        return <TagDetail tag={tag} childTags={childTags} onClose={close} />
    }

    return <DetailNotFound onBack={close} />
}
