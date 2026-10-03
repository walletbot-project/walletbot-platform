import { Button, CircularProgress } from 'actify'
import type { ComponentProps } from 'react'
import { ColorSwatches } from '@/components/color-swatches'
import { IconPicker } from '@/components/icon-picker'
import { ChoiceChip } from '@/components/m3/chip'
import { Icon } from '@/components/m3/icon'
import { COLOR_OPTIONS } from '@/lib/entity-colors'
import { useT } from '@/lib/i18n'

/**
 * The name-suggestion chip row the account and category forms open with,
 * porting the native `_nameSuggestions`: tapping one fills the name and
 * switches the icon to match.
 */
export function NameSuggestions({
    suggestions,
    resolveIcon,
    onPick,
}: {
    suggestions: readonly { label: string; icon: string }[]
    resolveIcon: (name: string) => { symbol: string; filled: boolean }
    onPick: (suggestion: { label: string; icon: string }) => void
}) {
    const t = useT()
    return (
        <section className="flex flex-col gap-2">
            <h2 className="m3-label-large text-on-surface">
                {t.accounts.suggestions}
            </h2>
            <div className="flex flex-wrap gap-2">
                {suggestions.map((suggestion) => {
                    const option = resolveIcon(suggestion.icon)
                    return (
                        <ChoiceChip
                            key={suggestion.icon}
                            label={suggestion.label}
                            selected={false}
                            onSelect={() => onPick(suggestion)}
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
    )
}

/** The "icon & color" section shared by the account and category forms. */
export function IconColorSection({
    icon,
    color,
    onIconChange,
    onColorChange,
    icons,
}: {
    icon: string
    color: string
    onIconChange: (icon: string) => void
    onColorChange: (color: string) => void
    icons: ComponentProps<typeof IconPicker>['icons']
}) {
    const t = useT()
    return (
        <section className="flex flex-col gap-3">
            <h2 className="m3-label-large text-on-surface">
                {t.common.iconAndColor}
            </h2>
            <div className="flex items-start gap-4">
                <IconPicker
                    icon={icon}
                    color={color}
                    onIconChange={onIconChange}
                    icons={icons}
                />
                <div className="flex-1">
                    <ColorSwatches
                        value={color}
                        onChange={onColorChange}
                        options={COLOR_OPTIONS}
                        themed
                    />
                </div>
            </div>
        </section>
    )
}

/** The full-width filled submit button with its in-flight spinner. */
export function FormSubmitButton({
    submitting,
    isDisabled,
    label,
}: {
    submitting: boolean
    isDisabled: boolean
    label: string
}) {
    return (
        <Button
            type="submit"
            variant="filled"
            className="w-full"
            isDisabled={isDisabled}
        >
            {submitting ? <CircularProgress isIndeterminate size="xs" /> : null}
            {label}
        </Button>
    )
}
