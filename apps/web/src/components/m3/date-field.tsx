import { useState } from 'react'
import { Calendar } from '@/components/ui/calendar'
import {
    Popover,
    PopoverContent,
    PopoverTrigger,
} from '@/components/ui/popover'
import { useFormatLocale, useT } from '@/lib/i18n'
import { PickerField } from './picker-field'

type DateFieldProps = {
    /** ISO `YYYY-MM-DD`, or an empty string when unset. */
    value: string
    onChange: (value: string) => void
    label?: string
    id?: string
    isDisabled?: boolean
    /** Compact framing, for rows that already carry their own label. */
    compact?: boolean
    className?: string
    /** Material Symbols ligature for the field's prefix glyph. */
    icon?: string
    /** Clear affordance, matching native's `_ReadonlyField` suffix. */
    onClear?: () => void
}

/** `YYYY-MM-DD` in local time — `toISOString` would shift across midnight. */
function toIsoDate(date: Date): string {
    const year = date.getFullYear().toString().padStart(4, '0')
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${year}-${month}-${day}`
}

function fromIsoDate(value: string): Date | undefined {
    if (!value) return undefined
    const [year, month, day] = value.split('-').map(Number)
    if (!year || !month || !day) return undefined
    const date = new Date(year, month - 1, day)
    return Number.isNaN(date.getTime()) ? undefined : date
}

/**
 * The Material 3 date field: a read-only field that opens a calendar, standing
 * in for the native `showDatePicker`. Not `<input type="date">` — that renders
 * the browser's own control and ignores the app's design system.
 */
export function DateField({
    value,
    onChange,
    label,
    id,
    isDisabled = false,
    compact = false,
    className,
    icon,
    onClear,
}: DateFieldProps) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const [open, setOpen] = useState(false)
    const selected = fromIsoDate(value)

    return (
        <Popover open={open} onOpenChange={setOpen}>
            <PopoverTrigger
                render={
                    <PickerField
                        id={id}
                        label={label ?? t.common.date}
                        value={
                            selected
                                ? selected.toLocaleDateString(formatLocale, {
                                      day: '2-digit',
                                      month: compact ? 'short' : 'long',
                                      year: 'numeric',
                                  })
                                : ''
                        }
                        placeholder={t.common.date}
                        icon={icon ?? 'calendar_month'}
                        onClear={onClear}
                        clearLabel={t.common.clear}
                        compact={compact}
                        className={className}
                        disabled={isDisabled}
                    />
                }
            />
            <PopoverContent className="w-auto p-0" align="start">
                <Calendar
                    mode="single"
                    selected={selected}
                    defaultMonth={selected}
                    onSelect={(date) => {
                        if (!date) return
                        onChange(toIsoDate(date))
                        setOpen(false)
                    }}
                    autoFocus
                />
            </PopoverContent>
        </Popover>
    )
}
