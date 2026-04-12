import { useForm } from '@tanstack/react-form'
import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useMutation } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { toast } from 'sonner'
import { ColorPicker } from '@/components/shared/color-picker'
import { ResponsiveDialog } from '@/components/shared/responsive-dialog'
import { Button } from '@/components/ui/button'
import { FormActions, FormField } from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

type TagItem = FunctionReturnType<typeof api.tags.queries.listTags>[number]

interface TagFormDialogProps {
    open: boolean
    onOpenChange: (open: boolean) => void
    tag?: TagItem
}

export function TagFormDialog({ open, onOpenChange, tag }: TagFormDialogProps) {
    const isEdit = !!tag
    const title = isEdit ? t('tags.edit') : t('tags.add')

    return (
        <ResponsiveDialog open={open} onOpenChange={onOpenChange} title={title}>
            <TagFormContent tag={tag} onSuccess={() => onOpenChange(false)} />
        </ResponsiveDialog>
    )
}

function TagFormContent({
    tag,
    onSuccess,
}: {
    tag?: TagItem
    onSuccess: () => void
}) {
    const isEdit = !!tag
    const createTag = useMutation(api.tags.mutations.createTag)
    const updateTag = useMutation(api.tags.mutations.updateTag)

    const form = useForm({
        defaultValues: {
            name: tag?.name ?? '',
            color: tag?.color ?? '#6b7280',
        },
        onSubmit: async ({ value }) => {
            try {
                if (isEdit && tag) {
                    await updateTag({
                        tagId: tag._id,
                        name: value.name.toLowerCase().trim(),
                        color: value.color,
                    })
                } else {
                    await createTag({
                        name: value.name.toLowerCase().trim(),
                        color: value.color,
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
                    <FormField field={field} label={t('tags.name')}>
                        <Input
                            value={field.state.value}
                            onChange={(e) => field.handleChange(e.target.value)}
                            onBlur={field.handleBlur}
                            placeholder={t('tags.name.placeholder')}
                        />
                    </FormField>
                )}
            />

            <form.Field
                name="color"
                children={(field) => (
                    <div className="flex flex-col gap-1.5">
                        <Label>{t('tags.color')}</Label>
                        <ColorPicker
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
