import { useForm } from '@tanstack/react-form'
import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useMutation } from 'convex/react'
import { Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { AccountSelector } from '@/components/shared/account-selector'
import { CategoryPicker } from '@/components/shared/category-picker'
import { CurrencyInput } from '@/components/shared/currency-input'
import { CurrencySelector } from '@/components/shared/currency-selector'
import { DatePickerField } from '@/components/shared/date-picker-field'
import { ResponsiveDialog } from '@/components/shared/responsive-dialog'
import { TagSelector } from '@/components/shared/tag-selector'
import { Button } from '@/components/ui/button'
import { FormActions, FormField } from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import { useAccounts } from '@/hooks/use-accounts'
import { useUserSettings } from '@/hooks/use-user-settings'
import { todayString } from '@/lib/format'
import type { Transaction } from './types'

interface TransactionFormDialogProps {
    open: boolean
    onOpenChange: (open: boolean) => void
    transaction?: Transaction
    onDelete?: () => void
}

type TxType = 'expense' | 'income' | 'transfer'

export function TransactionFormDialog({
    open,
    onOpenChange,
    transaction,
    onDelete,
}: TransactionFormDialogProps) {
    const isEdit = !!transaction
    const title = isEdit ? t('transactions.edit') : t('transactions.add')

    return (
        <ResponsiveDialog open={open} onOpenChange={onOpenChange} title={title}>
            <TransactionFormContent
                transaction={transaction}
                onSuccess={() => onOpenChange(false)}
                onDelete={onDelete}
            />
        </ResponsiveDialog>
    )
}

function TransactionFormContent({
    transaction,
    onSuccess,
    onDelete,
}: {
    transaction?: Transaction
    onSuccess: () => void
    onDelete?: () => void
}) {
    const isEdit = !!transaction
    const addTransaction = useMutation(
        api.transactions.mutations.addTransaction,
    )
    const updateTransaction = useMutation(
        api.transactions.mutations.updateTransaction,
    )
    const { defaultAccount } = useAccounts()
    const { settings } = useUserSettings()

    const form = useForm({
        defaultValues: {
            type: (transaction?.type ?? 'expense') as TxType,
            amount: transaction?.amount ?? 0,
            currency:
                transaction?.currency ??
                defaultAccount?.currency ??
                settings.defaultCurrency,
            description: transaction?.description ?? '',
            categoryId: transaction?.categoryId ?? undefined,
            fromAccountId:
                transaction?.fromAccountId ??
                (transaction ? undefined : defaultAccount?._id),
            toAccountId: transaction?.toAccountId ?? undefined,
            tags: transaction?.tags ?? [],
            date: transaction?.date ?? todayString(),
            notes: transaction?.notes ?? '',
        },
        onSubmit: async ({ value }) => {
            try {
                if (isEdit && transaction) {
                    await updateTransaction({
                        transactionId: transaction._id,
                        type: value.type,
                        amount: value.amount,
                        currency: value.currency as
                            | 'USD'
                            | 'ARS'
                            | 'EUR'
                            | 'BRL',
                        description: value.description,
                        categoryId:
                            value.type === 'transfer'
                                ? undefined
                                : value.categoryId,
                        tags: value.tags.length > 0 ? value.tags : undefined,
                        fromAccountId:
                            value.type === 'income'
                                ? undefined
                                : value.fromAccountId,
                        toAccountId:
                            value.type === 'expense'
                                ? undefined
                                : value.toAccountId,
                        date: value.date,
                        notes: value.notes || undefined,
                    })
                } else {
                    await addTransaction({
                        type: value.type,
                        amount: value.amount,
                        currency: value.currency as
                            | 'USD'
                            | 'ARS'
                            | 'EUR'
                            | 'BRL',
                        description: value.description,
                        categoryId:
                            value.type === 'transfer'
                                ? undefined
                                : value.categoryId,
                        tags: value.tags.length > 0 ? value.tags : undefined,
                        fromAccountId:
                            value.type === 'income'
                                ? undefined
                                : value.fromAccountId,
                        toAccountId:
                            value.type === 'expense'
                                ? undefined
                                : value.toAccountId,
                        date: value.date,
                        notes: value.notes || undefined,
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
            {/* Type selector */}
            <form.Field
                name="type"
                children={(field) => (
                    <Tabs
                        value={field.state.value}
                        onValueChange={(v) => field.handleChange(v as TxType)}
                    >
                        <TabsList className="w-full">
                            <TabsTrigger value="expense" className="flex-1">
                                {t('transactions.type.expense')}
                            </TabsTrigger>
                            <TabsTrigger value="income" className="flex-1">
                                {t('transactions.type.income')}
                            </TabsTrigger>
                            <TabsTrigger value="transfer" className="flex-1">
                                {t('transactions.type.transfer')}
                            </TabsTrigger>
                        </TabsList>
                    </Tabs>
                )}
            />

            {/* Amount + Currency */}
            <div className="grid grid-cols-3 gap-2">
                <form.Field
                    name="amount"
                    children={(field) => (
                        <div className="col-span-2">
                            <FormField
                                field={field}
                                label={t('transactions.amount')}
                            >
                                <form.Field
                                    name="currency"
                                    children={(currField) => (
                                        <CurrencyInput
                                            value={field.state.value}
                                            onChange={field.handleChange}
                                            currency={currField.state.value}
                                        />
                                    )}
                                />
                            </FormField>
                        </div>
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
            </div>

            {/* Description */}
            <form.Field
                name="description"
                children={(field) => (
                    <FormField
                        field={field}
                        label={t('transactions.description')}
                    >
                        <Input
                            value={field.state.value}
                            onChange={(e) => field.handleChange(e.target.value)}
                            onBlur={field.handleBlur}
                            placeholder={t(
                                'transactions.description.placeholder',
                            )}
                        />
                    </FormField>
                )}
            />

            {/* From Account (expense + transfer) */}
            <form.Subscribe
                selector={(state) => state.values.type}
                children={(type) =>
                    type !== 'income' ? (
                        <form.Field
                            name="fromAccountId"
                            children={(field) => (
                                <div className="flex flex-col gap-1.5">
                                    <Label>
                                        {t('transactions.fromAccount')}
                                    </Label>
                                    <AccountSelector
                                        value={field.state.value}
                                        onChange={(v) =>
                                            field.handleChange(
                                                v as typeof field.state.value,
                                            )
                                        }
                                    />
                                </div>
                            )}
                        />
                    ) : null
                }
            />

            {/* To Account (income + transfer) */}
            <form.Subscribe
                selector={(state) => state.values.type}
                children={(type) =>
                    type !== 'expense' ? (
                        <form.Field
                            name="toAccountId"
                            children={(field) => (
                                <div className="flex flex-col gap-1.5">
                                    <Label>{t('transactions.toAccount')}</Label>
                                    <AccountSelector
                                        value={field.state.value}
                                        onChange={(v) =>
                                            field.handleChange(
                                                v as typeof field.state.value,
                                            )
                                        }
                                    />
                                </div>
                            )}
                        />
                    ) : null
                }
            />

            {/* Category (expense + income, not transfer) */}
            <form.Subscribe
                selector={(state) => state.values.type}
                children={(type) =>
                    type !== 'transfer' ? (
                        <form.Field
                            name="categoryId"
                            children={(field) => (
                                <div className="flex flex-col gap-1.5">
                                    <Label>{t('transactions.category')}</Label>
                                    <CategoryPicker
                                        value={field.state.value}
                                        onChange={(v) =>
                                            field.handleChange(
                                                v as typeof field.state.value,
                                            )
                                        }
                                    />
                                </div>
                            )}
                        />
                    ) : null
                }
            />

            {/* Tags */}
            <form.Field
                name="tags"
                children={(field) => (
                    <div className="flex flex-col gap-1.5">
                        <Label>{t('transactions.tags')}</Label>
                        <TagSelector
                            value={field.state.value}
                            onChange={(v) =>
                                field.handleChange(
                                    v as typeof field.state.value,
                                )
                            }
                        />
                    </div>
                )}
            />

            {/* Date */}
            <form.Field
                name="date"
                children={(field) => (
                    <div className="flex flex-col gap-1.5">
                        <Label>{t('transactions.date')}</Label>
                        <DatePickerField
                            value={field.state.value}
                            onChange={field.handleChange}
                        />
                    </div>
                )}
            />

            {/* Notes */}
            <form.Field
                name="notes"
                children={(field) => (
                    <div className="flex flex-col gap-1.5">
                        <Label>{t('transactions.notes')}</Label>
                        <Textarea
                            value={field.state.value}
                            onChange={(e) => field.handleChange(e.target.value)}
                            placeholder={t('transactions.notes.placeholder')}
                            rows={2}
                        />
                    </div>
                )}
            />

            {/* Actions */}
            <form.Subscribe
                selector={(state) => [state.canSubmit, state.isSubmitting]}
                children={([canSubmit, isSubmitting]) => (
                    <FormActions>
                        {isEdit && onDelete && (
                            <Button
                                type="button"
                                variant="ghost"
                                size="icon-sm"
                                onClick={onDelete}
                                className="mr-auto"
                            >
                                <Trash2 className="size-4 text-destructive" />
                            </Button>
                        )}
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
