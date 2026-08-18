import { Plus } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { useT } from '@/lib/i18n'
import { CategoriesView } from '@/pages/insights/categories-view'
import { TagsView } from '@/pages/insights/tags-view'

export function Insights() {
    const t = useT()
    const [tab, setTab] = useState('categories')
    const [creatingCategory, setCreatingCategory] = useState(false)
    const [creatingTag, setCreatingTag] = useState(false)

    const handleCreate = () => {
        if (tab === 'categories') setCreatingCategory(true)
        else setCreatingTag(true)
    }

    return (
        <Tabs value={tab} onValueChange={setTab} className="flex-1 gap-0">
            <div className="flex items-center justify-between gap-2 border-b px-4 py-2">
                <TabsList>
                    <TabsTrigger value="categories">
                        {t.insights.categories}
                    </TabsTrigger>
                    <TabsTrigger value="tags">{t.insights.tags}</TabsTrigger>
                </TabsList>
                <Button size="sm" onClick={handleCreate}>
                    <Plus data-icon="inline-start" />
                    {t.insights.new}
                </Button>
            </div>

            <TabsContent value="categories" className="flex-1">
                <CategoriesView
                    creating={creatingCategory}
                    onCreatingChange={setCreatingCategory}
                />
            </TabsContent>
            <TabsContent value="tags" className="flex-1">
                <TagsView
                    creating={creatingTag}
                    onCreatingChange={setCreatingTag}
                />
            </TabsContent>
        </Tabs>
    )
}
