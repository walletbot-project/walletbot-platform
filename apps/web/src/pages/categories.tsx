import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useMutation } from 'convex/react'
import { Plus, Sparkles } from 'lucide-react'
import { useState } from 'react'
import { toast } from 'sonner'
import { CategoryFormDialog } from '@/components/categories/category-form-dialog'
import { CategoryTree } from '@/components/categories/category-tree'
import { PageHeader } from '@/components/shared/page-header'
import { Button } from '@/components/ui/button'

export function Categories() {
    const [addOpen, setAddOpen] = useState(false)
    const seed = useMutation(api.categories.mutations.seedSystemCategories)

    return (
        <>
            <PageHeader
                title={t('categories.title')}
                actions={
                    <div className="flex gap-2">
                        <Button
                            variant="outline"
                            size="sm"
                            onClick={async () => {
                                await seed()
                                toast.success(t('toast.success.saved'))
                            }}
                        >
                            <Sparkles className="size-4" />
                            Seed defaults
                        </Button>
                        <Button size="sm" onClick={() => setAddOpen(true)}>
                            <Plus className="size-4" />
                            {t('categories.add')}
                        </Button>
                    </div>
                }
            />
            <CategoryTree />
            <CategoryFormDialog open={addOpen} onOpenChange={setAddOpen} />
        </>
    )
}
