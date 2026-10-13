import {
    USABILITY_LONG_TEXT_MAX_LENGTH,
    USABILITY_TEXT_MAX_LENGTH,
    type UsabilityField,
    type UsabilityFieldValue,
} from '@wallet-bot/shared'
import { Button, TextField } from 'actify'
import { useEffect, useRef, useState } from 'react'
import { ChoiceChip } from '@/components/m3/chip'
import { Icon } from '@/components/m3/icon'
import { Checkbox } from '@/components/ui/checkbox'
import { useFormatLocale, useT } from '@/lib/i18n'
import { formatClock } from './session-data'

const AUTOSAVE_DELAY_MS = 800

type FieldInputProps = {
    field: UsabilityField
    value: UsabilityFieldValue | undefined
    onSave: (key: string, value: UsabilityFieldValue) => void
    onStamp: (key: string) => void
}

export function FieldInput({ field, value, onSave, onStamp }: FieldInputProps) {
    switch (field.kind) {
        case 'text':
        case 'longText':
            return <TextInput field={field} value={value} onSave={onSave} />
        case 'scale':
            return (
                <ChoiceInput
                    field={field}
                    value={value}
                    onSave={onSave}
                    options={[1, 2, 3, 4, 5].map((item) => ({
                        value: item,
                        label: String(item),
                    }))}
                    hints={field.hints}
                />
            )
        case 'yesNo':
            return <YesNoInput field={field} value={value} onSave={onSave} />
        case 'check':
            return <CheckInput field={field} value={value} onSave={onSave} />
        case 'choice':
            return (
                <ChoiceInput
                    field={field}
                    value={value}
                    onSave={onSave}
                    options={field.options}
                />
            )
        case 'multi':
            return <MultiInput field={field} value={value} onSave={onSave} />
        case 'timestamp':
            return (
                <StampInput
                    field={field}
                    value={value}
                    onSave={onSave}
                    onStamp={onStamp}
                />
            )
    }
}

function FieldLabel({ field }: { field: UsabilityField }) {
    return (
        <div className="flex flex-col gap-0.5">
            <span className="m3-body-medium text-on-surface">
                {field.label}
            </span>
            {field.hint ? (
                <span className="m3-body-small text-on-surface-variant">
                    {field.hint}
                </span>
            ) : null}
        </div>
    )
}

/**
 * Keeps what is being typed local and saves it after a pause or on blur.
 * While nobody is typing it shows the stored value, so notes written on the
 * other phone appear here too.
 */
function TextInput({ field, value, onSave }: Omit<FieldInputProps, 'onStamp'>) {
    const [draft, setDraft] = useState<string | null>(null)
    const timer = useRef<number | undefined>(undefined)
    const stored = typeof value === 'string' ? value : ''
    const multiline = field.kind === 'longText'

    useEffect(() => () => window.clearTimeout(timer.current), [])

    const commit = (text: string) => {
        window.clearTimeout(timer.current)
        if (text === stored) return
        onSave(field.key, text.trim() === '' ? null : text)
    }

    return (
        <div className="flex flex-col gap-1">
            <TextField
                variant="outlined"
                className="w-full"
                type={multiline ? 'textarea' : 'text'}
                label={field.label}
                value={draft ?? stored}
                maxLength={
                    multiline
                        ? USABILITY_LONG_TEXT_MAX_LENGTH
                        : USABILITY_TEXT_MAX_LENGTH
                }
                onChange={(next: string) => {
                    setDraft(next)
                    window.clearTimeout(timer.current)
                    timer.current = window.setTimeout(
                        () => commit(next),
                        AUTOSAVE_DELAY_MS,
                    )
                }}
                onBlur={() => {
                    if (draft === null) return
                    commit(draft)
                    setDraft(null)
                }}
            />
            {field.hint ? (
                <p className="m3-body-small px-4 text-on-surface-variant">
                    {field.hint}
                </p>
            ) : null}
        </div>
    )
}

function ChoiceInput<T extends string | number>({
    field,
    value,
    onSave,
    options,
    hints,
}: Omit<FieldInputProps, 'onStamp'> & {
    options: readonly { value: T; label: string }[]
    hints?: readonly string[]
}) {
    return (
        <div className="flex flex-col gap-2">
            <FieldLabel field={field} />
            <div className="flex flex-wrap gap-2">
                {options.map((option) => (
                    <ChoiceChip
                        key={option.value}
                        label={option.label}
                        selected={value === option.value}
                        onSelect={() =>
                            onSave(
                                field.key,
                                value === option.value ? null : option.value,
                            )
                        }
                    />
                ))}
            </div>
            {hints && hints.length > 0 ? (
                <ul className="m3-body-small flex flex-col gap-0.5 text-on-surface-variant">
                    {hints.map((hint) => (
                        <li key={hint}>{hint}</li>
                    ))}
                </ul>
            ) : null}
        </div>
    )
}

function YesNoInput({
    field,
    value,
    onSave,
}: Omit<FieldInputProps, 'onStamp'>) {
    const t = useT()
    return (
        <div className="flex flex-col gap-2">
            <FieldLabel field={field} />
            <div className="flex flex-wrap gap-2">
                {[
                    { option: true, label: t.usability.yes },
                    { option: false, label: t.usability.no },
                ].map(({ option, label }) => (
                    <ChoiceChip
                        key={label}
                        label={label}
                        selected={value === option}
                        onSelect={() =>
                            onSave(field.key, value === option ? null : option)
                        }
                    />
                ))}
            </div>
        </div>
    )
}

function CheckInput({
    field,
    value,
    onSave,
}: Omit<FieldInputProps, 'onStamp'>) {
    const id = `usability-${field.key}`
    return (
        <label
            htmlFor={id}
            className="flex cursor-pointer items-start gap-3 py-1"
        >
            <Checkbox
                id={id}
                className="mt-0.5"
                checked={value === true}
                onCheckedChange={(checked) =>
                    onSave(field.key, checked ? true : null)
                }
            />
            <span className="m3-body-medium text-on-surface">
                {field.label}
            </span>
        </label>
    )
}

function MultiInput({
    field,
    value,
    onSave,
}: Omit<FieldInputProps, 'onStamp'>) {
    if (field.kind !== 'multi') return null
    const selected = Array.isArray(value) ? value : []
    return (
        <div className="flex flex-col gap-2">
            <FieldLabel field={field} />
            <div className="flex flex-wrap gap-2">
                {field.options.map((option) => {
                    const isSelected = selected.includes(option.value)
                    return (
                        <ChoiceChip
                            key={option.value}
                            label={option.label}
                            selected={isSelected}
                            onSelect={() => {
                                const next = isSelected
                                    ? selected.filter(
                                          (item) => item !== option.value,
                                      )
                                    : [...selected, option.value]
                                onSave(field.key, next.length > 0 ? next : null)
                            }}
                        />
                    )
                })}
            </div>
        </div>
    )
}

function StampInput({ field, value, onSave, onStamp }: FieldInputProps) {
    const t = useT()
    const locale = useFormatLocale()
    const stamped = typeof value === 'number' ? value : undefined
    return (
        <div className="flex flex-wrap items-center gap-2">
            <span className="m3-body-medium text-on-surface">
                {field.label}
            </span>
            {stamped === undefined ? (
                <Button variant="tonal" onPress={() => onStamp(field.key)}>
                    <Icon name="timer" size={18} />
                    {t.usability.markStart}
                </Button>
            ) : (
                <span className="inline-flex items-center gap-1">
                    <span className="m3-title-small tabular-nums">
                        {formatClock(stamped, locale)}
                    </span>
                    <button
                        type="button"
                        aria-label={t.usability.clearTime}
                        onClick={() => onSave(field.key, null)}
                        className="m3-state-layer flex size-8 cursor-pointer items-center justify-center rounded-full text-on-surface-variant"
                    >
                        <Icon name="close" size={18} />
                    </button>
                </span>
            )}
        </div>
    )
}
