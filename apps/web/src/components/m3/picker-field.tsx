import type { ComponentProps, ReactNode } from 'react'
import { cn } from '@/lib/utils'
import { Icon } from './icon'

type PickerFieldProps = Omit<ComponentProps<'button'>, 'value'> & {
    label: string
    /** The current value, or empty to render the placeholder instead. */
    value: ReactNode
    placeholder?: string
    /** Material Symbols ligature for the field's prefix glyph. */
    icon?: string
    /**
     * Trailing glyph. Defaults to the dropdown caret and is ignored when
     * `onClear` is set — native's decoration puts the clear action in the
     * suffix slot, never a caret alongside it.
     */
    trailingIcon?: string
    leading?: ReactNode
    /** Renders the clear affordance in the trailing slot. */
    onClear?: () => void
    /** Accessible name for the clear action. */
    clearLabel?: string
    /**
     * Drops the label line and the field height, for rows that already carry a
     * label of their own (the transaction receipt, for instance).
     */
    compact?: boolean
}

/**
 * A read-only outlined field that opens a picker when tapped — the web stand-in
 * for native's `_ReadonlyField`: a prefix glyph, the label over the value, and
 * either a clear action or the dropdown caret in the trailing slot.
 *
 * Deliberately not a `<select>`: the platform control can't be themed to
 * Material 3, and its dropdown is the OS's, not the app's. Extra props land on
 * the button, so it can also serve as a popover trigger.
 */
export function PickerField({
    label,
    value,
    placeholder,
    icon,
    trailingIcon = 'arrow_drop_down',
    leading,
    onClear,
    clearLabel,
    compact = false,
    className,
    ...props
}: PickerFieldProps) {
    const isEmpty = value === null || value === undefined || value === ''
    const showClear = onClear !== undefined && !isEmpty

    return (
        <div className={cn('relative w-full', className)}>
            <button
                type="button"
                aria-label={compact ? label : undefined}
                {...props}
                className={cn(
                    'm3-state-layer flex w-full cursor-pointer items-center border border-outline text-left text-on-surface disabled:cursor-not-allowed disabled:opacity-38',
                    compact
                        ? 'h-9 gap-2 rounded-lg px-3'
                        : 'h-14 gap-3 rounded px-4',
                    showClear && !compact ? 'pr-13' : undefined,
                )}
            >
                {icon ? (
                    <Icon
                        name={icon}
                        className="shrink-0 text-on-surface-variant"
                    />
                ) : null}
                {leading}
                <span className="flex min-w-0 flex-1 flex-col">
                    {compact ? null : (
                        <span className="m3-body-small text-on-surface-variant">
                            {label}
                        </span>
                    )}
                    <span
                        className={cn(
                            'truncate',
                            compact ? 'm3-body-medium' : 'm3-body-large',
                            isEmpty && 'text-on-surface-variant',
                        )}
                    >
                        {isEmpty ? (placeholder ?? '—') : value}
                    </span>
                </span>
                {showClear ? null : (
                    <Icon
                        name={trailingIcon}
                        size={compact ? 20 : 24}
                        className="shrink-0 text-on-surface-variant"
                    />
                )}
            </button>
            {showClear ? (
                <button
                    type="button"
                    onClick={onClear}
                    aria-label={clearLabel ?? label}
                    className="m3-state-layer -translate-y-1/2 absolute top-1/2 right-2 flex size-10 cursor-pointer items-center justify-center rounded-full text-on-surface-variant"
                >
                    <Icon name="cancel" size={20} />
                </button>
            ) : null}
        </div>
    )
}
