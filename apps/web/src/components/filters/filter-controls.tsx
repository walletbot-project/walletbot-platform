/**
 * The small controls the filter editor is built from, kept apart from the two
 * editors so simple and advanced mode render the same chip rows, hints and
 * pickers. Each one stands in for a widget in native's `filter_sheet.dart`.
 */

import { SegmentedButton, SegmentedButtonSet } from 'actify'
import { type ReactNode, useState } from 'react'
import { ChoiceChip } from '@/components/m3/chip'
import { OptionSheet } from '@/components/m3/option-sheet'
import { PickerField } from '@/components/m3/picker-field'
import { useT } from '@/lib/i18n'

/** A titled block of the form — native's `_Section`. */
export function Section({
    title,
    children,
}: {
    title: string
    children: ReactNode
}) {
    return (
        <section className="flex flex-col gap-2">
            <h3 className="m3-title-small text-on-surface-variant">{title}</h3>
            {children}
        </section>
    )
}

/** Native's `_SubLabel` — a caption above a nested control. */
export function SubLabel({ children }: { children: ReactNode }) {
    return (
        <span className="m3-body-small text-on-surface-variant">
            {children}
        </span>
    )
}

/** Native's `_EmptyHint` — why a section has nothing to offer. */
export function EmptyHint({ children }: { children: ReactNode }) {
    return <p className="m3-body-medium text-on-surface-variant">{children}</p>
}

export type ChipOption = { id: string; label: string }

/**
 * Above this many chips a section collapses behind "show more", so a long
 * account or tag list can't take over the sheet — native's
 * `_chipCollapseThreshold`.
 */
const CHIP_COLLAPSE_THRESHOLD = 12

/**
 * A wrap of selectable chips that collapses past the threshold, keeping its own
 * expanded state — native's `_ExpandableChips`.
 */
export function ChipPicker({
    options,
    selected,
    onToggle,
    emptyText,
    single = false,
}: {
    options: readonly ChipOption[]
    selected: readonly string[]
    onToggle: (next: string[]) => void
    emptyText: string
    /** One choice at a time — re-tapping the selected chip clears it. */
    single?: boolean
}) {
    const t = useT()
    const [expanded, setExpanded] = useState(false)

    if (options.length === 0) return <EmptyHint>{emptyText}</EmptyHint>

    const collapses = options.length > CHIP_COLLAPSE_THRESHOLD
    const visible =
        collapses && !expanded
            ? options.slice(0, CHIP_COLLAPSE_THRESHOLD)
            : options

    const toggle = (id: string) => {
        if (single) {
            onToggle(selected.includes(id) ? [] : [id])
            return
        }
        onToggle(
            selected.includes(id)
                ? selected.filter((item) => item !== id)
                : [...selected, id],
        )
    }

    return (
        <div className="flex flex-col items-start gap-2">
            <div className="flex flex-wrap gap-2">
                {visible.map((option) => (
                    <ChoiceChip
                        key={option.id}
                        label={option.label}
                        selected={selected.includes(option.id)}
                        onSelect={() => toggle(option.id)}
                    />
                ))}
            </div>
            {collapses ? (
                <button
                    type="button"
                    onClick={() => setExpanded(!expanded)}
                    className="m3-label-large m3-state-layer cursor-pointer rounded px-2 py-1 text-primary"
                >
                    {expanded
                        ? t.filters.showLess
                        : t.filters.showMore({
                              count: options.length - CHIP_COLLAPSE_THRESHOLD,
                          })}
                </button>
            ) : null}
        </div>
    )
}

/**
 * A single-choice segmented control — native's `SegmentedButton`. The set is
 * what carries the styling; the segments only report presses.
 */
export function SegmentedChoice<T extends string>({
    options,
    value,
    onChange,
    label,
}: {
    options: readonly { value: T; label: string }[]
    value: T
    onChange: (next: T) => void
    /** Accessible name for the group. */
    label: string
}) {
    return (
        <SegmentedButtonSet aria-label={label} className="m3-segmented-set">
            {options.map((option) => (
                <SegmentedButton
                    key={option.value}
                    label={option.label}
                    selected={option.value === value}
                    noCheckmark
                    onPress={() => onChange(option.value)}
                />
            ))}
        </SegmentedButtonSet>
    )
}

/**
 * A read-only field that opens a list of options — the app's stand-in for a
 * dropdown (see `PickerField`), used for the advanced editor's field and
 * operator choices.
 */
export function PickerSelect({
    label,
    sheetTitle,
    value,
    options,
    onChange,
}: {
    label: string
    sheetTitle: string
    value: string
    options: readonly ChipOption[]
    onChange: (next: string) => void
}) {
    const [open, setOpen] = useState(false)
    const current = options.find((option) => option.id === value)

    return (
        <>
            <PickerField
                label={label}
                value={current?.label ?? value}
                onClick={() => setOpen(true)}
                compact
            />
            <OptionSheet
                open={open}
                onOpenChange={setOpen}
                title={sheetTitle}
                options={options}
                selected={value}
                onSelect={(next) => {
                    onChange(next)
                    setOpen(false)
                }}
            />
        </>
    )
}
