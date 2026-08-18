import { api } from '@wallet-bot/backend/api'
import { Button, IconButton, TabItem, Tabs } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useMemo } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { ListDetailLayout } from '@/components/m3/list-detail-layout'
import { StateMessage } from '@/components/m3/state-message'
import { useT } from '@/lib/i18n'
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

function newId() {
    return `${Date.now()}${Math.random().toString(36).slice(2, 8)}`
}

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

    const categories = useQuery(api.v1.categories.queries.listActiveWithCounts)
    const tags = useQuery(api.v1.tags.queries.listActiveWithCounts)

    const list = (
        <>
            <AppBar
                title={t.nav.insights}
                actions={
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
                }
            />
            <Tabs
                aria-label={t.nav.insights}
                selectedKey={tab}
                onSelectionChange={(key) => navigate(`/insights/${key}`)}
                className="flex min-h-0 flex-1 flex-col p-0 **:[[role=tablist]]:grid **:[[role=tablist]]:grid-cols-2 **:[[role=tablist]]:gap-0 **:[[role=tab]]:justify-center"
                contentClassName="min-h-0 flex-1 overflow-y-auto"
            >
                <TabItem key="categories" title={t.insights.categories}>
                    <CategoriesView
                        categories={categories}
                        onSelect={(id) =>
                            navigate(`/insights/categories/${id}`)
                        }
                    />
                </TabItem>
                <TabItem key="tags" title={t.insights.tags}>
                    <TagsView
                        tags={tags}
                        onSelect={(id) => navigate(`/insights/tags/${id}`)}
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
    const tags = useQuery(api.v1.tags.queries.listActiveWithCounts)
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
        await promise
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
        await promise
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
    const t = useT()
    const navigate = useNavigate()
    const tab = useInsightsTab()
    const { entityId } = useParams()
    const categories = useQuery(api.v1.categories.queries.listActiveWithCounts)
    const tags = useQuery(api.v1.tags.queries.listActiveWithCounts)

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

    if (loading) return null

    if (category !== null) {
        return <CategoryDetail category={category} onClose={close} />
    }
    if (tag !== null) {
        return <TagDetail tag={tag} childTags={childTags} onClose={close} />
    }

    return (
        <StateMessage
            icon="search_off"
            tone="error"
            title={t.common.notFoundTitle}
            detail={t.common.notFoundDescription}
            action={
                <Button variant="filled" onPress={close}>
                    {t.common.backToList}
                </Button>
            }
        />
    )
}
