import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { CategoriesView } from '@/pages/insights/categories-view'
import { TagsView } from '@/pages/insights/tags-view'

export function Insights() {
    return (
        <Tabs defaultValue="categories" className="flex-1 gap-0">
            <div className="border-b px-4 pt-2">
                <TabsList>
                    <TabsTrigger value="categories">Categories</TabsTrigger>
                    <TabsTrigger value="tags">Tags</TabsTrigger>
                </TabsList>
            </div>

            <TabsContent value="categories" className="flex-1">
                <CategoriesView />
            </TabsContent>
            <TabsContent value="tags" className="flex-1">
                <TagsView />
            </TabsContent>
        </Tabs>
    )
}
