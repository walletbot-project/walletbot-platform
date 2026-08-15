import { Button, CircularProgress, TextField } from 'actify'
import { type FormEvent, useState } from 'react'
import { ColorSwatches } from '@/components/color-swatches'
import { IconPicker } from '@/components/icon-picker'
import { ChoiceChip } from '@/components/m3/chip'
import { FormScreen } from '@/components/m3/form-screen'
import { Icon } from '@/components/m3/icon'
import {
    CATEGORY_DEFAULT_ICON,
    CATEGORY_ICONS,
    categoryIcon,
} from '@/lib/category-icons'
import { CATEGORY_DEFAULT_COLOR, COLOR_OPTIONS } from '@/lib/entity-colors'
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
                <section className="flex flex-col gap-2">
                    <h2 className="m3-label-large text-on-surface">
                        {t.accounts.suggestions}
                    </h2>
                    <div className="flex flex-wrap gap-2">
                        {NAME_SUGGESTIONS.map((suggestion) => {
                            const label = suggestion.label(t)
                            const option = categoryIcon(suggestion.icon)
                            return (
                                <ChoiceChip
                                    key={suggestion.icon}
                                    label={label}
                                    selected={false}
                                    onSelect={() => {
                                        setName(label)
                                        setIcon(suggestion.icon)
                                    }}
                                    leading={
                                        <Icon
                                            name={option.symbol}
                                            filled={option.filled}
                                            size={18}
                                        />
                                    }
                                />
                            )
                        })}
                    </div>
                </section>

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

                <section className="flex flex-col gap-3">
                    <h2 className="m3-label-large text-on-surface">
                        {t.common.iconAndColor}
                    </h2>
                    <div className="flex items-start gap-4">
                        <IconPicker
                            icon={icon}
                            color={color}
                            onIconChange={setIcon}
                            icons={CATEGORY_ICONS}
                        />
                        <div className="flex-1">
                            <ColorSwatches
                                value={color}
                                onChange={setColor}
                                options={COLOR_OPTIONS}
                            />
                        </div>
                    </div>
                </section>

                <Button
                    type="submit"
                    variant="filled"
                    className="w-full"
                    isDisabled={submitting || !name.trim()}
                >
                    {submitting ? (
                        <CircularProgress isIndeterminate size="xs" />
                    ) : null}
                    {t.common.create}
                </Button>
            </form>
        </FormScreen>
    )
}
