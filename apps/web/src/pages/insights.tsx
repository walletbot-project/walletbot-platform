import { api } from '@wallet-bot/backend/api'
import { IconButton, TabItem, Tabs } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useMemo, useState } from 'react'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { DividedView } from '@/components/m3/divided-view'
import { Icon } from '@/components/m3/icon'
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

/**
 * Insights: the Categories/Tags tab view with a single divided-view host.
 *
 * The detail pane sits outside the tab pages and is shared across both tabs —
 * it holds the last thing opened, a category or a tag — matching the native
 * screen (apps/native/lib/screens/insights.dart).
 */
export function Insights() {
    const t = useT()
    const [tab, setTab] = useState<InsightsTab>('categories')
    const [creatingCategory, setCreatingCategory] = useState(false)
    const [creatingTag, setCreatingTag] = useState(false)

    // At most one selection across both tabs — last opened wins, like the
    // shared pane on native.
    const [selected, setSelected] = useState<
        { kind: 'category'; id: string } | { kind: 'tag'; id: string } | null
    >(null)

    const categories = useQuery(api.v1.categories.queries.listActiveWithCounts)
    const tags = useQuery(api.v1.tags.queries.listActiveWithCounts)
    const createCategory = useMutation(api.v1.categories.mutations.create)
    const createTag = useMutation(api.v1.tags.mutations.create)

    // Derive the open entity from the live query so edits saved in the detail
    // are reflected immediately (a stored snapshot would go stale on save).
    const selectedCategory: CategorySummary | null = useMemo(() => {
        if (selected?.kind !== 'category' || categories === undefined) {
            return null
        }
        const category = categories.find((c) => c.id === selected.id)
        return category
            ? {
                  id: category.id,
                  name: category.name,
                  icon: category.icon,
                  color: category.color,
                  description: category.description,
              }
            : null
    }, [categories, selected])

    const selectedTag: TagSummary | null = useMemo(() => {
        if (selected?.kind !== 'tag' || tags === undefined) return null
        const tag = tags.find((item) => item.id === selected.id)
        return tag
            ? {
                  id: tag.id,
                  name: tag.name,
                  color: tag.color,
                  parentId: tag.parentId,
              }
            : null
    }, [tags, selected])

    const selectedTagChildren = useMemo(
        () =>
            selectedTag
                ? (tags ?? [])
                      .filter((item) => item.parentId === selectedTag.id)
                      .map((item) => ({
                          id: item.id,
                          name: item.name,
                          color: item.color,
                          parentId: item.parentId,
                      }))
                : [],
        [tags, selectedTag],
    )

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
        setCreatingCategory(false)
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
        setCreatingTag(false)
    }

    // The divided view's pane hosts one occupant at a time, so opening a form
    // clears the selection and vice versa (the `AdaptiveDetailView` rule).
    const handleAdd = () => {
        setSelected(null)
        if (tab === 'categories') setCreatingCategory(true)
        else setCreatingTag(true)
    }

    const openDetail = (next: { kind: 'category' | 'tag'; id: string }) => {
        setCreatingCategory(false)
        setCreatingTag(false)
        setSelected(next)
    }

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
                        onPress={handleAdd}
                        className="text-on-surface-variant"
                    >
                        <Icon name="add" />
                    </IconButton>
                }
            />
            <Tabs
                aria-label={t.nav.insights}
                selectedKey={tab}
                onSelectionChange={(key) => setTab(key as InsightsTab)}
                className="flex min-h-0 flex-1 flex-col p-0 **:[[role=tablist]]:grid **:[[role=tablist]]:grid-cols-2 **:[[role=tablist]]:gap-0 **:[[role=tab]]:justify-center"
                contentClassName="min-h-0 flex-1 overflow-y-auto"
            >
                <TabItem key="categories" title={t.insights.categories}>
                    <CategoriesView
                        categories={categories}
                        onSelect={(id) => openDetail({ kind: 'category', id })}
                    />
                </TabItem>
                <TabItem key="tags" title={t.insights.tags}>
                    <TagsView
                        tags={tags}
                        onSelect={(id) => openDetail({ kind: 'tag', id })}
                    />
                </TabItem>
            </Tabs>
        </>
    )

    const detail = selectedCategory ? (
        <CategoryDetail
            category={selectedCategory}
            onClose={() => setSelected(null)}
        />
    ) : selectedTag ? (
        <TagDetail
            tag={selectedTag}
            childTags={selectedTagChildren}
            onClose={() => setSelected(null)}
        />
    ) : null

    const form = creatingCategory ? (
        <CategoryForm
            onClose={() => setCreatingCategory(false)}
            onSubmit={handleCreateCategory}
        />
    ) : creatingTag ? (
        <TagForm
            title={t.insights.newTag}
            submitLabel={t.common.create}
            parentOptions={parentOptions}
            onClose={() => setCreatingTag(false)}
            onSubmit={handleCreateTag}
        />
    ) : null

    return (
        <DividedView
            list={list}
            detail={detail}
            detailTitle={
                selectedCategory?.name ?? selectedTag?.name ?? t.nav.insights
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
            onDismiss={() => setSelected(null)}
            form={form}
        />
    )
}
