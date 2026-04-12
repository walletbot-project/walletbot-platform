import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useMutation } from 'convex/react'
import { Plus, Sparkles } from 'lucide-react'
import { useState } from 'react'
import { toast } from 'sonner'
import { AccountFormDialog } from '@/components/accounts/account-form-dialog'
import { AccountList } from '@/components/accounts/account-list'
import { PageHeader } from '@/components/shared/page-header'
import { Button } from '@/components/ui/button'

export function Accounts() {
    const [addOpen, setAddOpen] = useState(false)
    const seed = useMutation(api.accounts.mutations.seedDefaultAccounts)

    return (
        <>
            <PageHeader
                title={t('accounts.title')}
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
                            {t('accounts.add')}
                        </Button>
                    </div>
                }
            />
            <AccountList />
            <AccountFormDialog open={addOpen} onOpenChange={setAddOpen} />
        </>
    )
}
