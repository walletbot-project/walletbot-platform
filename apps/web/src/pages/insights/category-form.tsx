import { TextField } from 'actify'
import { type FormEvent, useState } from 'react'
import {
    FormSubmitButton,
    IconColorSection,
    NameSuggestions,
} from '@/components/entity-form-sections'
import { FormScreen } from '@/components/m3/form-screen'
import {
    CATEGORY_DEFAULT_ICON,
    CATEGORY_ICONS,
    categoryIcon,
} from '@/lib/category-icons'
import { CATEGORY_DEFAULT_COLOR } from '@/lib/entity-colors'
import { type Messages, useT } from '@/lib/i18n'

export type CategoryFormValue = {
    name: string
    description: string
    color: string
    icon: string
}

/** Name + icon presets, mirroring the native `_nameSuggestions`. */
const NAME_SUGGESTIONS: { label: (t: Messages) => string; icon: string }[] = [
    {
        label: (t) => t.insights.categorySuggestionGroceries,
        icon: 'shopping_cart',
    },
    { label: (t) => t.insights.categorySuggestionTransport, icon: 'transport' },
    { label: (t) => t.insights.categorySuggestionUtilities, icon: 'receipt' },
]

/**
 * Category creation, porting `CreateCategoryScreen`. Lives in the divided
 * view's pane on expanded windows and over the window on smaller ones.
 */
export function CategoryForm({
    onClose,
    onSubmit,
}: {
    onClose: () => void
    onSubmit: (value: CategoryFormValue) => Promise<void>
}) {
    const t = useT()
    const [name, setName] = useState('')
    const [description, setDescription] = useState('')
    const [color, setColor] = useState(CATEGORY_DEFAULT_COLOR)
    const [icon, setIcon] = useState(CATEGORY_DEFAULT_ICON)
    const [submitting, setSubmitting] = useState(false)

    const handleSubmit = async (event: FormEvent) => {
        event.preventDefault()
        const trimmed = name.trim()
        if (!trimmed) return
        setSubmitting(true)
        try {
            await onSubmit({
                name: trimmed,
                description: description.trim(),
                color,
                icon,
            })
        } finally {
            setSubmitting(false)
        }
    }

    return (
        <FormScreen title={t.insights.newCategory} onClose={onClose}>
            <form onSubmit={handleSubmit} className="flex flex-col gap-6 p-4">
                <NameSuggestions
                    suggestions={NAME_SUGGESTIONS.map((suggestion) => ({
                        label: suggestion.label(t),
                        icon: suggestion.icon,
                    }))}
                    resolveIcon={categoryIcon}
                    onPick={(suggestion) => {
                        setName(suggestion.label)
                        setIcon(suggestion.icon)
                    }}
                />

                <TextField
                    variant="outlined"
                    className="w-full"
                    label={t.common.name}
                    value={name}
                    onChange={setName}
                    placeholder={t.insights.categoryNamePlaceholder}
                    isRequired
                    isDisabled={submitting}
                    autoFocus
                />

                <TextField
                    variant="outlined"
                    type="textarea"
                    className="w-full"
                    label={t.insights.categoryDescriptionOptional}
                    value={description}
                    onChange={setDescription}
                    isDisabled={submitting}
                />

                <IconColorSection
                    icon={icon}
                    color={color}
                    onIconChange={setIcon}
                    onColorChange={setColor}
                    icons={CATEGORY_ICONS}
                />

                <FormSubmitButton
                    submitting={submitting}
                    isDisabled={submitting || !name.trim()}
                    label={t.common.create}
                />
            </form>
        </FormScreen>
    )
}
