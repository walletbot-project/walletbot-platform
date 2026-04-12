import { useForm } from '@tanstack/react-form'
import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useMutation } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { toast } from 'sonner'
import { AccountSelector } from '@/components/shared/account-selector'
import { CategoryPicker } from '@/components/shared/category-picker'
import { CurrencyInput } from '@/components/shared/currency-input'
import { CurrencySelector } from '@/components/shared/currency-selector'
import { DatePickerField } from '@/components/shared/date-picker-field'
import { ResponsiveDialog } from '@/components/shared/responsive-dialog'
import { TagSelector } from '@/components/shared/tag-selector'
import { Button } from '@/components/ui/button'
import { Combobox } from '@/components/ui/combobox'
import { FormActions, FormField } from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { useAccounts } from '@/hooks/use-accounts'
import { useUserSettings } from '@/hooks/use-user-settings'
import { todayString } from '@/lib/format'

type Recurrence = FunctionReturnType<
    typeof api.recurrences.queries.listRecurrences
>[number]
type TxType = 'expense' | 'income' | 'transfer'
type Frequency = 'daily' | 'weekly' | 'monthly' | 'yearly'

const FREQ_OPTIONS = [
    { value: 'daily', label: 'Daily' },
    { value: 'weekly', label: 'Weekly' },
    { value: 'monthly', label: 'Monthly' },
    { value: 'yearly', label: 'Yearly' },
]

interface RecurrenceFormDialogProps {
    open: boolean
    onOpenChange: (open: boolean) => void
    recurrence?: Recurrence
}

export function RecurrenceFormDialog({
    open,
    onOpenChange,
    recurrence,
}: RecurrenceFormDialogProps) {
    const isEdit = !!recurrence
    const title = isEdit
        ? 'Edit Recurring Transaction'
        : 'Add Recurring Transaction'

    return (
        <ResponsiveDialog open={open} onOpenChange={onOpenChange} title={title}>
            <RecurrenceFormContent
                recurrence={recurrence}
                onSuccess={() => onOpenChange(false)}
            />
        </ResponsiveDialog>
    )
}

function RecurrenceFormContent({
    recurrence,
    onSuccess,
}: {
    recurrence?: Recurrence
    onSuccess: () => void
}) {
    const isEdit = !!recurrence
    const createRecurrence = useMutation(
        api.recurrences.mutations.createRecurrence,
    )
    const updateRecurrence = useMutation(
        api.recurrences.mutations.updateRecurrence,
    )
    const { defaultAccount } = useAccounts()
    const { settings } = useUserSettings()

    const form = useForm({
        defaultValues: {
            type: (recurrence?.type ?? 'expense') as TxType,
            amount: recurrence?.amount ?? 0,
            currency:
                recurrence?.currency ??
                defaultAccount?.currency ??
                settings.defaultCurrency,
            description: recurrence?.description ?? '',
            categoryId: recurrence?.categoryId ?? undefined,
            fromAccountId: recurrence?.fromAccountId ?? defaultAccount?._id,
            toAccountId: recurrence?.toAccountId ?? undefined,
            tags: recurrence?.tags ?? [],
            notes: recurrence?.notes ?? '',
            frequency: (recurrence?.frequency ?? 'monthly') as Frequency,
            interval: recurrence?.interval ?? 1,
            startDate: recurrence?.startDate ?? todayString(),
            endDate: recurrence?.endDate ?? undefined,
        },
        onSubmit: async ({ value }) => {
            try {
                if (isEdit && recurrence) {
                    await updateRecurrence({
                        recurrenceId: recurrence._id,
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
                        notes: value.notes || undefined,
                        frequency: value.frequency,
                        interval: value.interval,
                        endDate: value.endDate,
                    })
                } else {
                    await createRecurrence({
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
                        notes: value.notes || undefined,
                        frequency: value.frequency,
                        interval: value.interval,
                        startDate: value.startDate,
                        endDate: value.endDate,
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

            {/* Recurrence config */}
            <div className="grid grid-cols-2 gap-2">
                <form.Field
                    name="frequency"
                    children={(field) => (
                        <div className="flex flex-col gap-1.5">
                            <Label>Frequency</Label>
                            <Combobox
                                value={[field.state.value]}
                                onChange={(v) => {
                                    if (v[0])
                                        field.handleChange(v[0] as Frequency)
                                }}
                                options={FREQ_OPTIONS}
                            />
                        </div>
                    )}
                />
                <form.Field
                    name="interval"
                    children={(field) => (
                        <FormField field={field} label="Every N">
                            <Input
                                type="number"
                                min={1}
                                value={field.state.value}
                                onChange={(e) =>
                                    field.handleChange(
                                        parseInt(e.target.value, 10) || 1,
                                    )
                                }
                            />
                        </FormField>
                    )}
                />
            </div>

            <div className="grid grid-cols-2 gap-2">
                <form.Field
                    name="startDate"
                    children={(field) => (
                        <div className="flex flex-col gap-1.5">
                            <Label>Start date</Label>
                            <DatePickerField
                                value={field.state.value}
                                onChange={field.handleChange}
                            />
                        </div>
                    )}
                />
                <form.Field
                    name="endDate"
                    children={(field) => (
                        <div className="flex flex-col gap-1.5">
                            <Label>End date</Label>
                            <DatePickerField
                                value={field.state.value}
                                onChange={field.handleChange}
                                placeholder="Never"
                            />
                        </div>
                    )}
                />
            </div>

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
