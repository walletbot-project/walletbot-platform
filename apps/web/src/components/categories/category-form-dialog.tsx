import { useForm } from '@tanstack/react-form'
import { api } from '@wallet-bot/backend/api'
import { type TranslationKey, t } from '@wallet-bot/shared'
import { useMutation } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { useMemo } from 'react'
import { toast } from 'sonner'
import { ColorPicker } from '@/components/shared/color-picker'
import { ResponsiveDialog } from '@/components/shared/responsive-dialog'
import { Button } from '@/components/ui/button'
import { Combobox } from '@/components/ui/combobox'
import { FormActions, FormField } from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useCategories } from '@/hooks/use-categories'

type Category = FunctionReturnType<
    typeof api.categories.queries.listCategories
>[number]

interface CategoryFormDialogProps {
    open: boolean
    onOpenChange: (open: boolean) => void
    category?: Category | Category['children'][number]
}

export function CategoryFormDialog({
    open,
    onOpenChange,
    category,
}: CategoryFormDialogProps) {
    const isEdit = !!category
    const title = isEdit ? t('categories.edit') : t('categories.add')

    return (
        <ResponsiveDialog open={open} onOpenChange={onOpenChange} title={title}>
            <CategoryFormContent
                category={category}
                onSuccess={() => onOpenChange(false)}
            />
        </ResponsiveDialog>
    )
}

function CategoryFormContent({
    category,
    onSuccess,
}: {
    category?: Category | Category['children'][number]
    onSuccess: () => void
}) {
    const isEdit = !!category
    const createCategory = useMutation(api.categories.mutations.createCategory)
    const updateCategory = useMutation(api.categories.mutations.updateCategory)
    const { categories } = useCategories()

    const parentOptions = useMemo(
        () =>
            categories
                .filter((c) => !('children' in c && c._id === category?._id))
                .map((c) => ({
                    value: c._id,
                    label: `${c.icon} ${c.isSystem ? t(c.name as TranslationKey) : c.name}`,
                })),
        [categories, category],
    )

    const isSystem = category && 'isSystem' in category && category.isSystem

    const form = useForm({
        defaultValues: {
            name: category
                ? isSystem
                    ? t(category.name as TranslationKey)
                    : category.name
                : '',
            icon: category?.icon ?? '\uD83D\uDCE6',
            color: category?.color ?? '#6b7280',
            parentId:
                'parentId' in (category ?? {})
                    ? ((category as Category['children'][number])?.parentId ??
                      undefined)
                    : undefined,
        },
        onSubmit: async ({ value }) => {
            try {
                if (isEdit && category) {
                    await updateCategory({
                        categoryId: category._id,
                        name: isSystem ? undefined : value.name,
                        icon: value.icon,
                        color: value.color,
                        parentId: value.parentId,
                    })
                } else {
                    await createCategory({
                        name: value.name,
                        icon: value.icon,
                        color: value.color,
                        parentId: value.parentId,
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
                    <FormField field={field} label={t('categories.name')}>
                        <Input
                            value={field.state.value}
                            onChange={(e) => field.handleChange(e.target.value)}
                            onBlur={field.handleBlur}
                            placeholder={t('categories.name.placeholder')}
                            disabled={!!isSystem}
                        />
                    </FormField>
                )}
            />

            <form.Field
                name="icon"
                children={(field) => (
                    <FormField field={field} label={t('categories.icon')}>
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
                name="color"
                children={(field) => (
                    <div className="flex flex-col gap-1.5">
                        <Label>{t('categories.color')}</Label>
                        <ColorPicker
                            value={field.state.value}
                            onChange={field.handleChange}
                        />
                    </div>
                )}
            />

            <form.Field
                name="parentId"
                children={(field) => (
                    <div className="flex flex-col gap-1.5">
                        <Label>{t('categories.parent')}</Label>
                        <Combobox
                            value={field.state.value ? [field.state.value] : []}
                            onChange={(v) =>
                                field.handleChange(
                                    v[0] as typeof field.state.value,
                                )
                            }
                            options={parentOptions}
                            placeholder={t('categories.parent.none')}
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
