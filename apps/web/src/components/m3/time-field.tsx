import type { ChangeEvent } from 'react'
import { useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'
import { Icon } from './icon'

type TimeFieldProps = {
    /** `HH:mm` in 24h form, or an empty string when unset. */
    value: string
    onChange: (value: string) => void
    label: string
    /** Renders a clear action once a time is set. */
    onClear?: () => void
    isDisabled?: boolean
    /** Row-sized boxes, for contexts that can't give the field its full height. */
    compact?: boolean
}

function splitTime(value: string): { hour: string; minute: string } {
    const [hour = '', minute = ''] = value.split(':')
    return { hour, minute }
}

function clampPart(raw: string, max: number): string {
    const digits = raw.replace(/\D/g, '').slice(0, 2)
    if (digits === '') return ''
    return String(Math.min(Number(digits), max)).padStart(digits.length, '0')
}

/**
 * Material 3's time *input* — the two-box keyboard variant of the time picker
 * (the dial's counterpart). Used instead of `<input type="time">`, which
 * renders the browser's own control.
 *
 * A part is only reported upward once both are present, so a half-typed time
 * never reaches the caller as a malformed value.
 */
export function TimeField({
    value,
    onChange,
    label,
    onClear,
    isDisabled = false,
    compact = false,
}: TimeFieldProps) {
    const t = useT()
    const { hour, minute } = splitTime(value)

    const update = (nextHour: string, nextMinute: string) => {
        if (nextHour === '' && nextMinute === '') {
            onChange('')
            return
        }
        onChange(
            `${nextHour.padStart(2, '0')}:${(nextMinute || '0').padStart(2, '0')}`,
        )
    }

    const handleHour = (event: ChangeEvent<HTMLInputElement>) =>
        update(clampPart(event.target.value, 23), minute)
    const handleMinute = (event: ChangeEvent<HTMLInputElement>) =>
        update(hour || '0', clampPart(event.target.value, 59))

    const partClass = cn(
        'rounded bg-surface-container-highest text-center text-on-surface tabular-nums outline-none',
        compact ? 'm3-body-medium h-9 w-11' : 'm3-display-small h-16 w-18',
        'focus-visible:bg-primary-container focus-visible:text-on-primary-container',
        'disabled:cursor-not-allowed disabled:opacity-38',
    )

    return (
        <div className={cn('flex items-center', compact ? 'gap-1' : 'gap-2')}>
            <span className="sr-only">{label}</span>
            <input
                type="text"
                inputMode="numeric"
                aria-label={t.common.hour}
                value={hour}
                onChange={handleHour}
                disabled={isDisabled}
                placeholder="--"
                className={partClass}
            />
            <span
                className={cn(
                    'text-on-surface',
                    compact ? 'm3-body-medium' : 'm3-display-small',
                )}
            >
                :
            </span>
            <input
                type="text"
                inputMode="numeric"
                aria-label={t.common.minute}
                value={minute}
                onChange={handleMinute}
                disabled={isDisabled}
                placeholder="--"
                className={partClass}
            />
            {onClear && value ? (
                <button
                    type="button"
                    onClick={onClear}
                    aria-label={t.common.clear}
                    className="m3-state-layer flex size-11 shrink-0 cursor-pointer items-center justify-center rounded-full text-on-surface-variant"
                >
                    <Icon name="close" size={20} />
                </button>
            ) : null}
        </div>
    )
}
