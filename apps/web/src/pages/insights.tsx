import { Plus } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { CategoriesView } from '@/pages/insights/categories-view'
import { TagsView } from '@/pages/insights/tags-view'

export function Insights() {
    const [tab, setTab] = useState('categories')
    const [creatingCategory, setCreatingCategory] = useState(false)
    const [creatingTag, setCreatingTag] = useState(false)

    const handleCreate = () => {
        if (tab === 'categories') setCreatingCategory(true)
        else setCreatingTag(true)
    }

    return (
        <Tabs value={tab} onValueChange={setTab} className="flex-1 gap-0">
            <div className="flex items-center justify-between gap-2 border-b px-4 pt-2">
                <TabsList>
                    <TabsTrigger value="categories">Categories</TabsTrigger>
                    <TabsTrigger value="tags">Tags</TabsTrigger>
                </TabsList>
                <Button size="sm" onClick={handleCreate}>
                    <Plus data-icon="inline-start" />
                    New
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
