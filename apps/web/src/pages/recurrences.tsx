import { Plus } from 'lucide-react'
import { useState } from 'react'
import { RecurrenceFormDialog } from '@/components/recurrences/recurrence-form-dialog'
import { RecurrenceList } from '@/components/recurrences/recurrence-list'
import { PageHeader } from '@/components/shared/page-header'
import { Button } from '@/components/ui/button'

export function Recurrences() {
    const [addOpen, setAddOpen] = useState(false)

    return (
        <>
            <PageHeader
                title="Recurring Transactions"
                actions={
                    <Button size="sm" onClick={() => setAddOpen(true)}>
                        <Plus className="size-4" />
                        Add recurring
                    </Button>
                }
            />
            <RecurrenceList />
            <RecurrenceFormDialog open={addOpen} onOpenChange={setAddOpen} />
        </>
    )
}
