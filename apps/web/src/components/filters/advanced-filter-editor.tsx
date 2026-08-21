/**
 * The advanced filter editor: the canonical condition tree, edited as a tree.
 * A port of native's `_GroupEditor` / `_ConditionEditor`
 * (apps/native/lib/components/filter_sheet.dart) — same fields, same operators,
 * same nesting depth, so a filter written here opens unchanged on the phone and
 * a filter written there is fully editable here.
 */

import {
    ACCOUNT_DIRECTIONS,
    type AccountDirection,
    DATE_PRESETS,
    type FilterCondition,
    type FilterGroup,
    type FilterNode,
    isFilterGroup,
    TAG_MATCHES,
    type TagMatch,
    TXN_STATUSES,
    TXN_TYPES,
} from '@wallet-bot/shared'
import { IconButton, Switch, TextField } from 'actify'
import { ChoiceChip } from '@/components/m3/chip'
import { DateField } from '@/components/m3/date-field'
import { Icon } from '@/components/m3/icon'
import { type Messages, useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'
import {
    type ChipOption,
    ChipPicker,
    EmptyHint,
    PickerSelect,
    SegmentedChoice,
    SubLabel,
} from './filter-controls'
import {
    accountDirectionLabel,
    asAmountRange,
    asDateRange,
    asStringList,
    centsToText,
    datePresetLabel,
    defaultCondition,
    FILTER_FIELDS,
    filterFieldLabel,
    operatorLabel,
    operatorsFor,
    tagMatchLabel,
    textToCents,
    txnStatusLabel,
    txnTypeLabel,
} from './labels'

/** The selectable values a condition can reference, loaded once by the sheet. */
export type FilterOptions = {
    accounts: readonly ChipOption[]
    categories: readonly ChipOption[]
    tags: readonly ChipOption[]
    currencies: readonly ChipOption[]
}

/** How deep the editor lets groups nest — native's `_GroupEditor.maxDepth`. */
const MAX_DEPTH = 2

export function AdvancedFilterEditor({
    root,
    options,
    onChange,
}: {
    root: FilterGroup
    options: FilterOptions
    onChange: (next: FilterGroup) => void
}) {
    return (
        <GroupEditor
            group={root}
            options={options}
            depth={0}
            onChange={onChange}
        />
    )
}

function GroupEditor({
    group,
    options,
    depth,
    onChange,
    onRemove,
}: {
    group: FilterGroup
    options: FilterOptions
    depth: number
    onChange: (next: FilterGroup) => void
    onRemove?: () => void
}) {
    const t = useT()

    const replaceChild = (index: number, node: FilterNode) => {
        const children = [...group.children]
        children[index] = node
        onChange({ ...group, children })
    }

    const removeChild = (index: number) => {
        onChange({
            ...group,
            children: group.children.filter((_, at) => at !== index),
        })
    }

    const addChild = (node: FilterNode) => {
        onChange({ ...group, children: [...group.children, node] })
    }

    return (
        <div
            className={cn(
                'flex flex-col gap-3 rounded-xl border border-outline-variant p-3',
                depth === 0 ? 'bg-surface' : 'bg-surface-container-highest',
            )}
        >
            <div className="flex flex-wrap items-center gap-2">
                <SegmentedChoice
                    label={t.filters.operator}
                    value={group.combinator === 'or' ? 'or' : 'and'}
                    options={[
                        { value: 'and', label: t.filters.combinatorAnd },
                        { value: 'or', label: t.filters.combinatorOr },
                    ]}
                    onChange={(combinator) =>
                        onChange({ ...group, combinator })
                    }
                />
                <ChoiceChip
                    label={t.filters.negate}
                    selected={group.not === true}
                    // `not` is written only when set, so a plain group keeps
                    // serializing to the same JSON it arrived as.
                    onSelect={() =>
                        onChange(
                            group.not === true
                                ? {
                                      combinator: group.combinator,
                                      children: group.children,
                                  }
                                : { ...group, not: true },
                        )
                    }
                />
                <span className="flex-1" />
                {onRemove ? (
                    <IconButton
                        aria-label={t.filters.deleteGroup}
                        onPress={onRemove}
                        className="text-on-surface-variant"
                    >
                        <Icon name="delete" />
                    </IconButton>
                ) : null}
            </div>

            {group.children.length === 0 ? (
                <EmptyHint>{t.filters.addConditionToStart}</EmptyHint>
            ) : (
                <div className="flex flex-col gap-2">
                    {group.children.map((child, index) =>
                        isFilterGroup(child) ? (
                            <GroupEditor
                                // Position is the only identity a node has —
                                // conditions carry no id, and two conditions on
                                // the same field are legal.
                                key={`group-${index}`}
                                group={child}
                                options={options}
                                depth={depth + 1}
                                onChange={(next) => replaceChild(index, next)}
                                onRemove={() => removeChild(index)}
                            />
                        ) : (
                            <ConditionEditor
                                key={`condition-${index}`}
                                condition={child}
                                options={options}
                                onChange={(next) => replaceChild(index, next)}
                                onRemove={() => removeChild(index)}
                            />
                        ),
                    )}
                </div>
            )}

            <div className="flex flex-wrap gap-2">
                <AddButton
                    icon="add"
                    label={t.filters.condition}
                    onClick={() => addChild(defaultCondition('type'))}
                />
                {depth < MAX_DEPTH ? (
                    <AddButton
                        icon="account_tree"
                        label={t.filters.group}
                        onClick={() =>
                            addChild({ combinator: 'and', children: [] })
                        }
                    />
                ) : null}
            </div>
        </div>
    )
}

function AddButton({
    icon,
    label,
    onClick,
}: {
    icon: string
    label: string
    onClick: () => void
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className="m3-label-large m3-state-layer flex h-10 cursor-pointer items-center gap-2 rounded-[20px] border border-outline px-4 text-on-surface-variant"
        >
            <Icon name={icon} size={18} />
            {label}
        </button>
    )
}

function ConditionEditor({
    condition,
    options,
    onChange,
    onRemove,
}: {
    condition: FilterCondition
    options: FilterOptions
    onChange: (next: FilterCondition) => void
    onRemove: () => void
}) {
    const t = useT()
    const operators = operatorsFor(condition.field)
    // A stored operator the field no longer offers falls back to its first, so
    // a condition from a newer client stays editable instead of rendering blank.
    const operator = operators.includes(condition.operator)
        ? condition.operator
        : operators[0]
    const current: FilterCondition = { ...condition, operator }

    return (
        <div className="flex flex-col gap-3 rounded-xl bg-surface p-3">
            <div className="flex items-end gap-2">
                <div className="min-w-0 flex-1">
                    <PickerSelect
                        label={t.filters.field}
                        sheetTitle={t.filters.chooseField}
                        value={condition.field}
                        options={FILTER_FIELDS.map((field) => ({
                            id: field,
                            label: filterFieldLabel(field, t),
                        }))}
                        // Changing the field resets the value: what a `type`
                        // condition holds is meaningless to `amount`.
                        onChange={(field) => onChange(defaultCondition(field))}
                    />
                </div>
                <div className="min-w-0 flex-1">
                    <PickerSelect
                        label={t.filters.operator}
                        sheetTitle={t.filters.chooseOperator}
                        value={operator}
                        options={operators.map((value) => ({
                            id: value,
                            label: operatorLabel(value, t),
                        }))}
                        onChange={(next) =>
                            onChange({ ...condition, operator: next })
                        }
                    />
                </div>
                <IconButton
                    aria-label={t.filters.deleteCondition}
                    onPress={onRemove}
                    className="shrink-0 text-on-surface-variant"
                >
                    <Icon name="delete" />
                </IconButton>
            </div>

            <ConditionValueEditor
                condition={current}
                options={options}
                onChange={onChange}
                t={t}
            />
        </div>
    )
}

function ConditionValueEditor({
    condition,
    options,
    onChange,
    t,
}: {
    condition: FilterCondition
    options: FilterOptions
    onChange: (next: FilterCondition) => void
    t: Messages
}) {
    const selected = asStringList(condition.value)
    const setValue = (value: unknown) => onChange({ ...condition, value })

    switch (condition.field) {
        case 'type':
            return (
                <ChipPicker
                    options={TXN_TYPES.map((value) => ({
                        id: value,
                        label: txnTypeLabel(value, t),
                    }))}
                    selected={selected}
                    onToggle={setValue}
                    emptyText=""
                />
            )
        case 'status':
            return (
                <ChipPicker
                    options={TXN_STATUSES.map((value) => ({
                        id: value,
                        label: txnStatusLabel(value, t),
                    }))}
                    selected={selected}
                    onToggle={setValue}
                    emptyText=""
                />
            )
        case 'account':
            return (
                <div className="flex flex-col gap-3">
                    <ChipPicker
                        options={options.accounts}
                        selected={selected}
                        onToggle={setValue}
                        emptyText={t.filters.noAccountsYet}
                    />
                    <div className="flex flex-col items-start gap-1">
                        <SubLabel>{t.filters.direction}</SubLabel>
                        <SegmentedChoice
                            label={t.filters.direction}
                            value={condition.direction ?? 'either'}
                            options={ACCOUNT_DIRECTIONS.map(
                                (value: AccountDirection) => ({
                                    value,
                                    label: accountDirectionLabel(value, t),
                                }),
                            )}
                            onChange={(direction) =>
                                onChange({ ...condition, direction })
                            }
                        />
                    </div>
                </div>
            )
        case 'category':
            return (
                <ChipPicker
                    options={options.categories}
                    selected={selected}
                    onToggle={setValue}
                    emptyText={t.filters.noCategoriesYet}
                />
            )
        case 'tag':
            return (
                <div className="flex flex-col gap-3">
                    <ChipPicker
                        options={options.tags}
                        selected={selected}
                        onToggle={setValue}
                        emptyText={t.filters.noTagsYet}
                    />
                    <div className="flex flex-wrap items-center gap-3">
                        <SubLabel>{t.filters.match}</SubLabel>
                        <SegmentedChoice
                            label={t.filters.match}
                            value={condition.match ?? 'any'}
                            options={TAG_MATCHES.map((value: TagMatch) => ({
                                value,
                                label: tagMatchLabel(value, t),
                            }))}
                            onChange={(match) =>
                                onChange({ ...condition, match })
                            }
                        />
                    </div>
                    {/*
                     * The switch names itself; a wrapping <label> would leave
                     * the control unassociated as far as static analysis (and
                     * some screen readers) can tell.
                     */}
                    <div className="flex items-center justify-between gap-3">
                        <span className="m3-body-medium text-on-surface">
                            {t.filters.includeSubtags}
                        </span>
                        <Switch
                            aria-label={t.filters.includeSubtags}
                            isSelected={condition.includeSubtags === true}
                            onChange={(includeSubtags) =>
                                onChange({ ...condition, includeSubtags })
                            }
                        />
                    </div>
                </div>
            )
        case 'currency':
            return (
                <ChipPicker
                    options={options.currencies}
                    selected={selected}
                    onToggle={setValue}
                    emptyText={t.filters.noCurrenciesYet}
                    single
                />
            )
        case 'date':
            return (
                <DateValueEditor
                    condition={condition}
                    onChange={onChange}
                    t={t}
                />
            )
        case 'amount':
            return (
                <AmountValueEditor
                    condition={condition}
                    onChange={onChange}
                    t={t}
                />
            )
        case 'text':
            return (
                <TextField
                    variant="outlined"
                    className="w-full"
                    aria-label={t.filters.text}
                    placeholder={t.filters.searchHint}
                    value={
                        typeof condition.value === 'string'
                            ? condition.value
                            : ''
                    }
                    onChange={setValue}
                />
            )
        default:
            return <EmptyHint>{t.filters.unsupportedField}</EmptyHint>
    }
}

function DateValueEditor({
    condition,
    onChange,
    t,
}: {
    condition: FilterCondition
    onChange: (next: FilterCondition) => void
    t: Messages
}) {
    if (condition.operator === 'relative') {
        const preset =
            typeof condition.value === 'string' ? condition.value : ''
        return (
            <ChipPicker
                options={DATE_PRESETS.map((value) => ({
                    id: value,
                    label: datePresetLabel(value, t),
                }))}
                selected={preset ? [preset] : []}
                onToggle={(next) =>
                    onChange({ ...condition, value: next[0] ?? '' })
                }
                emptyText=""
                single
            />
        )
    }

    const range = asDateRange(condition.value)
    return (
        <div className="grid grid-cols-2 gap-3">
            <DateField
                label={t.filters.rangeStart}
                compact
                value={isoDay(range?.from)}
                // A one-sided range is not representable on the wire, so the
                // other end follows the one being set until the user moves it.
                onChange={(from) =>
                    onChange({
                        ...condition,
                        value: { from, to: isoDay(range?.to) || from },
                    })
                }
            />
            <DateField
                label={t.filters.rangeEnd}
                compact
                value={isoDay(range?.to)}
                onChange={(to) =>
                    onChange({
                        ...condition,
                        value: { from: isoDay(range?.from) || to, to },
                    })
                }
            />
        </div>
    )
}

function AmountValueEditor({
    condition,
    onChange,
    t,
}: {
    condition: FilterCondition
    onChange: (next: FilterCondition) => void
    t: Messages
}) {
    const { min, max } = asAmountRange(condition.value)
    const write = (next: { min: number | null; max: number | null }) =>
        onChange({ ...condition, value: next })

    if (condition.operator === '>=') {
        return (
            <TextField
                variant="outlined"
                className="w-full"
                label={t.filters.minimum}
                inputMode="decimal"
                value={centsToText(min)}
                onChange={(raw) => write({ min: textToCents(raw), max: null })}
            />
        )
    }
    if (condition.operator === '<=') {
        return (
            <TextField
                variant="outlined"
                className="w-full"
                label={t.filters.maximum}
                inputMode="decimal"
                value={centsToText(max)}
                onChange={(raw) => write({ min: null, max: textToCents(raw) })}
            />
        )
    }
    return (
        <div className="grid grid-cols-2 gap-3">
            <TextField
                variant="outlined"
                className="w-full"
                label={t.filters.minimum}
                inputMode="decimal"
                value={centsToText(min)}
                onChange={(raw) => write({ min: textToCents(raw), max })}
            />
            <TextField
                variant="outlined"
                className="w-full"
                label={t.filters.maximum}
                inputMode="decimal"
                value={centsToText(max)}
                onChange={(raw) => write({ min, max: textToCents(raw) })}
            />
        </div>
    )
}

/**
 * The `YYYY-MM-DD` `DateField` reads and writes. Stored values may carry a full
 * ISO timestamp (native writes `toIso8601String()`), so the day is taken off
 * the front rather than parsed and reformatted.
 */
function isoDay(value: string | undefined): string {
    return value ? value.slice(0, 10) : ''
}
