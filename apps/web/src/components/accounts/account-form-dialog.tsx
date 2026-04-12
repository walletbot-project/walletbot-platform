import { useForm } from '@tanstack/react-form'
import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useMutation } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { toast } from 'sonner'
import { CurrencySelector } from '@/components/shared/currency-selector'
import { ResponsiveDialog } from '@/components/shared/responsive-dialog'
import { Button } from '@/components/ui/button'
import { FormActions, FormField } from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { useUserSettings } from '@/hooks/use-user-settings'

type Account = FunctionReturnType<
    typeof api.accounts.queries.listAccounts
>[number]

interface AccountFormDialogProps {
    open: boolean
    onOpenChange: (open: boolean) => void
    account?: Account
}

export function AccountFormDialog({
    open,
    onOpenChange,
    account,
}: AccountFormDialogProps) {
    const isEdit = !!account
    const title = isEdit ? t('accounts.edit') : t('accounts.add')

    return (
        <ResponsiveDialog open={open} onOpenChange={onOpenChange} title={title}>
            <AccountFormContent
                account={account}
                onSuccess={() => onOpenChange(false)}
            />
        </ResponsiveDialog>
    )
}

function AccountFormContent({
    account,
    onSuccess,
}: {
    account?: Account
    onSuccess: () => void
}) {
    const isEdit = !!account
    const createAccount = useMutation(api.accounts.mutations.createAccount)
    const updateAccount = useMutation(api.accounts.mutations.updateAccount)
    const { settings } = useUserSettings()

    const form = useForm({
        defaultValues: {
            name: account?.name ?? '',
            type: (account?.type ?? 'asset') as 'asset' | 'liability',
            icon: account?.icon ?? '\uD83C\uDFE6',
            currency: account?.currency ?? settings.defaultCurrency,
        },
        onSubmit: async ({ value }) => {
            try {
                if (isEdit && account) {
                    await updateAccount({
                        accountId: account._id,
                        name: value.name,
                        type: value.type,
                        icon: value.icon,
                        currency: value.currency as
                            | 'USD'
                            | 'ARS'
                            | 'EUR'
                            | 'BRL',
                    })
                } else {
                    await createAccount({
                        name: value.name,
                        type: value.type,
                        icon: value.icon,
                        currency: value.currency as
                            | 'USD'
                            | 'ARS'
                            | 'EUR'
                            | 'BRL',
                    })
                }
                toast.success(t('toast.success.saved'))
                onSuccess()
            } catch (err) {
                toast.error(
                    err instanceof Error
                        ? err.message
                        : t('toast.error.generic'),
                )
            }
        },
    })

    return (
        <form
            onSubmit={(e) => {
                e.preventDefault()
                form.handleSubmit()
            }}
            className="flex flex-col gap-4"
        >
            <form.Field
                name="name"
                children={(field) => (
                    <FormField field={field} label={t('accounts.name')}>
                        <Input
                            value={field.state.value}
                            onChange={(e) => field.handleChange(e.target.value)}
                            onBlur={field.handleBlur}
                            placeholder={t('accounts.name.placeholder')}
                        />
                    </FormField>
                )}
            />

            <form.Field
                name="type"
                children={(field) => (
                    <div className="flex flex-col gap-1.5">
                        <Label>{t('accounts.type')}</Label>
                        <Tabs
                            value={field.state.value}
                            onValueChange={(v) =>
                                field.handleChange(v as 'asset' | 'liability')
                            }
                        >
                            <TabsList className="w-full">
                                <TabsTrigger value="asset" className="flex-1">
                                    {t('accounts.type.asset')}
                                </TabsTrigger>
                                <TabsTrigger
                                    value="liability"
                                    className="flex-1"
                                >
                                    {t('accounts.type.liability')}
                                </TabsTrigger>
                            </TabsList>
                        </Tabs>
                        <p className="text-xs text-muted-foreground">
                            {field.state.value === 'asset'
                                ? t('accounts.type.asset.description')
                                : t('accounts.type.liability.description')}
                        </p>
                    </div>
                )}
            />

            <form.Field
                name="icon"
                children={(field) => (
                    <FormField field={field} label={t('accounts.icon')}>
                        <Input
                            value={field.state.value}
                            onChange={(e) => field.handleChange(e.target.value)}
                            onBlur={field.handleBlur}
                            className="w-20 text-center text-lg"
                        />
                    </FormField>
                )}
            />

            <form.Field
                name="currency"
                children={(field) => (
                    <div className="flex flex-col gap-1.5">
                        <Label>{t('accounts.currency')}</Label>
                        <CurrencySelector
                            value={field.state.value}
                            onChange={field.handleChange}
                        />
                    </div>
                )}
            />

            <form.Subscribe
                selector={(state) => [state.canSubmit, state.isSubmitting]}
                children={([canSubmit, isSubmitting]) => (
                    <FormActions>
                        <Button type="submit" disabled={!canSubmit}>
                            {isSubmitting
                                ? t('toast.loading')
                                : t('common.save')}
                        </Button>
                    </FormActions>
                )}
            />
        </form>
    )
}
