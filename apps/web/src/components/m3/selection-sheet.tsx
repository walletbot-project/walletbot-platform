import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { BottomSheet } from './bottom-sheet'
import { GroupedCard } from './grouped-card'
import { Icon } from './icon'

export type SelectionChoice<T extends string> = {
    value: T
    /** Material Symbols ligature name for the leading glyph. */
    icon: string
    label: string
}

type SelectionSheetProps<T extends string> = {
    open: boolean
    onOpenChange: (open: boolean) => void
    title: string
    description: string
    selected: T
    choices: readonly SelectionChoice<T>[]
    onSelect: (value: T) => void
}

/**
 * The single-choice bottom sheet the settings screen uses, matching the native
 * `_SelectionSheet`: a headline, a one-line description, and the options as a
 * grouped card list with the active one marked.
 */
export function SelectionSheet<T extends string>({
    open,
    onOpenChange,
    title,
    description,
    selected,
    choices,
    onSelect,
}: SelectionSheetProps<T>) {
    return (
        <BottomSheet open={open} onOpenChange={onOpenChange} title={title}>
            <div className="flex flex-col px-4 pb-6">
                <h2 className="m3-headline-small px-2 font-semibold">
                    {title}
                </h2>
                <p className="m3-body-medium mt-1 px-2 text-on-surface-variant">
                    {description}
                </p>
                <div
                    className="mt-5 flex flex-col"
                    style={{ gap: GROUP_SPACING }}
                >
                    {choices.map((choice, index) => {
                        const isSelected = choice.value === selected
                        return (
                            <GroupedCard
                                key={choice.value}
                                radius={groupedRadius(index, choices.length)}
                                onClick={() => onSelect(choice.value)}
                            >
                                <div className="flex items-center gap-4 px-4 py-4">
                                    <Icon
                                        name={choice.icon}
                                        filled
                                        className={
                                            isSelected
                                                ? 'text-primary'
                                                : 'text-on-surface-variant'
                                        }
                                    />
                                    <span
                                        className={
                                            isSelected
                                                ? 'm3-body-large flex-1 font-semibold text-primary'
                                                : 'm3-body-large flex-1'
                                        }
                                    >
                                        {choice.label}
                                    </span>
                                    {isSelected ? (
                                        <Icon
                                            name="check_circle"
                                            filled
                                            className="text-primary"
                                        />
                                    ) : null}
                                </div>
                            </GroupedCard>
                        )
                    })}
                </div>
            </div>
        </BottomSheet>
    )
}
