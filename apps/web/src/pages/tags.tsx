import { t } from '@wallet-bot/shared'
import { Plus } from 'lucide-react'
import { useState } from 'react'
import { PageHeader } from '@/components/shared/page-header'
import { TagFormDialog } from '@/components/tags/tag-form-dialog'
import { TagList } from '@/components/tags/tag-list'
import { Button } from '@/components/ui/button'

export function Tags() {
    const [addOpen, setAddOpen] = useState(false)

    return (
        <>
            <PageHeader
                title={t('tags.title')}
                actions={
                    <Button size="sm" onClick={() => setAddOpen(true)}>
                        <Plus className="size-4" />
                        {t('tags.add')}
                    </Button>
                }
            />
            <TagList />
            <TagFormDialog open={addOpen} onOpenChange={setAddOpen} />
        </>
    )
}
