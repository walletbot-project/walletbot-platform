import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'
import { Icon } from './icon'

const CHIP_BASE =
    'm3-label-large m3-state-layer inline-flex h-8 shrink-0 items-center gap-2 rounded-lg px-4 whitespace-nowrap'

/**
 * M3 choice chip — one selection out of a set, matching Flutter's
 * `ChoiceChip(showCheckmark: false)`: an outlined shell when unselected, the
 * secondary container when selected.
 */
export function ChoiceChip({
    label,
    selected,
    onSelect,
    leading,
}: {
    label: string
    selected: boolean
    onSelect: () => void
    /** Optional avatar/glyph before the label, matching Flutter's `avatar`. */
    leading?: ReactNode
}) {
    return (
        <button
            type="button"
            aria-pressed={selected}
            onClick={onSelect}
            className={cn(
                CHIP_BASE,
                'cursor-pointer',
                leading ? 'pl-2' : undefined,
                selected
                    ? 'bg-secondary-container text-on-secondary-container'
                    : 'border border-outline text-on-surface-variant',
            )}
        >
            {leading}
            {label}
        </button>
    )
}

/**
 * M3 assist chip, matching Flutter's `ActionChip`: an outlined shell that runs
 * one action.
 */
export function AssistChip({
    label,
    onPress,
}: {
    label: string
    onPress: () => void
}) {
    return (
        <button
            type="button"
            onClick={onPress}
            className={cn(
                CHIP_BASE,
                'max-w-full cursor-pointer border border-outline text-on-surface',
            )}
        >
            <span className="truncate">{label}</span>
        </button>
    )
}

/**
 * M3 input chip — a committed filter with a trailing remove affordance,
 * matching Flutter's `InputChip(onDeleted: …)`.
 */
export function InputChip({
    children,
    onRemove,
    removeLabel,
}: {
    children: ReactNode
    onRemove: () => void
    removeLabel: string
}) {
    return (
        <span
            className={cn(
                CHIP_BASE,
                'border border-outline pr-2 text-on-surface-variant',
            )}
        >
            {children}
            <button
                type="button"
                onClick={onRemove}
                aria-label={removeLabel}
                className="m3-state-layer flex size-[18px] cursor-pointer items-center justify-center rounded-full"
            >
                <Icon name="close" size={18} />
            </button>
        </span>
    )
}
