import { api } from '@wallet-bot/backend/api'
import { Select, SelectOption } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { type FormEvent, type ReactNode, useId, useState } from 'react'
import { toast } from 'sonner'
import { AccountIcon } from '@/components/account-icon'
import { CategoryIcon } from '@/components/category-icon'
import { ColorSwatches } from '@/components/color-swatches'
import { IconPicker } from '@/components/icon-picker'
import { BottomSheet } from '@/components/m3/bottom-sheet'
import { Icon } from '@/components/m3/icon'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Skeleton } from '@/components/ui/skeleton'
import { Textarea } from '@/components/ui/textarea'
import type { ChatMessage, EditableToolName } from '@/hooks/use-voice'
import { ACCOUNT_ICONS } from '@/lib/account-icons'
import { CATEGORY_ICONS } from '@/lib/category-icons'
import {
    ACCOUNT_DEFAULT_COLOR,
    CATEGORY_DEFAULT_COLOR,
    COLOR_OPTIONS,
    normalizeColor,
    useReadableAccent,
} from '@/lib/entity-colors'
import {
    type Messages,
    transactionName,
    useFormatLocale,
    useT,
} from '@/lib/i18n'
import { normalizeTagColor } from '@/lib/tag-colors'
import { cn } from '@/lib/utils'
import { accountErrorMessage } from '@/pages/accounts/account-errors'
import { TransactionDetail } from './activity/transaction-detail'

type ActionResultMessage = Extract<ChatMessage, { kind: 'action-result' }>

const TRANSACTION_TOOL_NAMES = [
    'addExpense',
    'addIncome',
    'addTransfer',
    'addBalanceAdjustment',
    'updateTransaction',
] as const satisfies readonly EditableToolName[]

type TransactionToolName = (typeof TRANSACTION_TOOL_NAMES)[number]

function isTransactionToolName(
    toolName: EditableToolName,
): toolName is TransactionToolName {
    return (TRANSACTION_TOOL_NAMES as readonly EditableToolName[]).includes(
        toolName,
    )
}

/** Collection keys can't be empty strings, so "no parent" gets a sentinel. */
const NO_PARENT = '__none__'

export function ActionWidget({ message }: { message: ActionResultMessage }) {
    const { toolName, entityId } = message

    if (isTransactionToolName(toolName)) {
        return (
            <TransactionActionWidget
                entityId={entityId}
                wasUpdated={toolName === 'updateTransaction'}
            />
        )
    }

    switch (toolName) {
        case 'createAccount':
        case 'updateAccount':
            return (
                <AccountActionWidget
                    entityId={entityId}
                    wasUpdated={toolName === 'updateAccount'}
                />
            )
        case 'createCategory':
        case 'updateCategory':
            return (
                <CategoryActionWidget
                    entityId={entityId}
                    wasUpdated={toolName === 'updateCategory'}
                />
            )
        case 'createTag':
        case 'updateTag':
            return (
                <TagActionWidget
                    entityId={entityId}
                    wasUpdated={toolName === 'updateTag'}
                />
            )
        default:
            return assertNever(toolName)
    }
}

type TxnType = 'expense' | 'income' | 'transfer' | 'balance_adjustment'

function TransactionActionWidget({
    entityId,
    wasUpdated,
}: {
    entityId: string
    wasUpdated: boolean
}) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const txn = useQuery(api.v1.transactions.queries.get, { id: entityId })
    const accounts = useQuery(api.v1.accounts.queries.list, {
        includeArchived: true,
    })
    const [editOpen, setEditOpen] = useState(false)

    if (txn === undefined || accounts === undefined) return <ActionSkeleton />
    if (txn === null) return null

    const account = accounts.find((item) => item.id === txn.accountId)
    const toAccount = txn.toAccountId
        ? accounts.find((item) => item.id === txn.toAccountId)
        : undefined
    const { icon, iconCls, label } = txnTypeConfig(txn.type, t)
    const amount =
        txn.type === 'transfer' &&
        txn.toAmount !== undefined &&
        txn.toCurrency !== undefined
            ? `${formatAmount(txn.amount, txn.currency)} → ${formatAmount(txn.toAmount, txn.toCurrency)}`
            : txn.type === 'balance_adjustment' &&
                txn.balanceAfter !== undefined
              ? formatAmount(txn.balanceAfter, txn.currency)
              : formatAmount(txn.amount, txn.currency)
    const deletedAccount = t.transaction.deletedAccount
    const location =
        txn.type === 'transfer'
            ? `${account?.name ?? deletedAccount} → ${toAccount?.name ?? deletedAccount}`
            : (account?.name ?? deletedAccount)

    return (
        <>
            <ActionCard>
                <div className={cn('rounded-full p-1.5', iconCls.bg)}>
                    <Icon
                        name={icon}
                        filled
                        size={16}
                        className={iconCls.text}
                    />
                </div>
                <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">
                        {transactionName(txn.name, txn.type, t)}
                    </p>
                    <p className="truncate text-xs text-muted-foreground">
                        {wasUpdated
                            ? t.actionWidget.transactionUpdated({ type: label })
                            : t.actionWidget.transactionRecorded({
                                  type: label,
                              })}{' '}
                        · {amount} · {location} ·{' '}
                        {epochToNumericDate(txn.date, formatLocale)} ·{' '}
                        {epochToHHMM(txn.date, formatLocale)}
                    </p>
                </div>
                <EditButton onClick={() => setEditOpen(true)} />
            </ActionCard>
            <BottomSheet
                open={editOpen}
                onOpenChange={setEditOpen}
                title={t.transaction.editActivity}
            >
                {editOpen ? (
                    <TransactionDetail
                        transactionId={txn.id}
                        initialEditing
                        onClose={() => setEditOpen(false)}
                    />
                ) : null}
            </BottomSheet>
        </>
    )
}

function AccountActionWidget({
    entityId,
    wasUpdated,
}: {
    entityId: string
    wasUpdated: boolean
}) {
    const t = useT()
    const paint = useReadableAccent()
    const account = useQuery(api.v1.accounts.queries.get, { id: entityId })
    const updateAccount = useMutation(api.v1.accounts.mutations.update)
    const [editOpen, setEditOpen] = useState(false)
    if (account === undefined) return <ActionSkeleton />
    if (account === null) return null

    const accent = paint(normalizeColor(account.color, ACCOUNT_DEFAULT_COLOR))
    return (
        <>
            <ActionCard>
                <EntityIcon color={accent}>
                    <AccountIcon name={account.icon} size={16} color={accent} />
                </EntityIcon>
                <ActionCopy
                    title={account.name}
                    detail={t.actionWidget.accountDetail({
                        currency: account.currency,
                        updated: wasUpdated,
                    })}
                />
                <EditButton onClick={() => setEditOpen(true)} />
            </ActionCard>
            <ActionSheet
                open={editOpen}
                onOpenChange={setEditOpen}
                title={t.actionWidget.editAccount}
            >
                <EntityEditContent
                    title={t.actionWidget.editAccount}
                    initialName={account.name}
                    initialDescription={account.description ?? ''}
                    initialColor={normalizeColor(
                        account.color,
                        ACCOUNT_DEFAULT_COLOR,
                    )}
                    initialIcon={account.icon ?? 'wallet'}
                    icons={ACCOUNT_ICONS}
                    savedToast={t.actionWidget.accountSaved}
                    errorToast={(error) =>
                        accountErrorMessage(error, t, t.common.saveFailed)
                    }
                    onSave={(value) =>
                        updateAccount({ id: account.id, ...value })
                    }
                    onClose={() => setEditOpen(false)}
                />
            </ActionSheet>
        </>
    )
}

function CategoryActionWidget({
    entityId,
    wasUpdated,
}: {
    entityId: string
    wasUpdated: boolean
}) {
    const t = useT()
    const paint = useReadableAccent()
    const category = useQuery(api.v1.categories.queries.get, { id: entityId })
    const updateCategory = useMutation(api.v1.categories.mutations.update)
    const [editOpen, setEditOpen] = useState(false)
    if (category === undefined) return <ActionSkeleton />
    if (category === null) return null

    const accent = paint(normalizeColor(category.color, CATEGORY_DEFAULT_COLOR))
    return (
        <>
            <ActionCard>
                <EntityIcon color={accent}>
                    <CategoryIcon
                        name={category.icon}
                        size={16}
                        color={accent}
                    />
                </EntityIcon>
                <ActionCopy
                    title={category.name}
                    detail={t.actionWidget.categoryDetail({
                        updated: wasUpdated,
                    })}
                />
                <EditButton onClick={() => setEditOpen(true)} />
            </ActionCard>
            <ActionSheet
                open={editOpen}
                onOpenChange={setEditOpen}
                title={t.actionWidget.editCategory}
            >
                <EntityEditContent
                    title={t.actionWidget.editCategory}
                    initialName={category.name}
                    initialDescription={category.description ?? ''}
                    initialColor={normalizeColor(
                        category.color,
                        CATEGORY_DEFAULT_COLOR,
                    )}
                    initialIcon={category.icon ?? 'category'}
                    icons={CATEGORY_ICONS}
                    savedToast={t.actionWidget.categorySaved}
                    errorToast={t.common.saveFailed}
                    onSave={(value) =>
                        updateCategory({ id: category.id, ...value })
                    }
                    onClose={() => setEditOpen(false)}
                />
            </ActionSheet>
        </>
    )
}

/**
 * The account/category edit form — one component, since the two differed only
 * in mutation, defaults, icon set and toast copy. The description is sent only
 * when it changed, so an untouched field can't clobber a concurrent edit.
 */
function EntityEditContent({
    title,
    initialName,
    initialDescription,
    initialColor,
    initialIcon,
    icons,
    savedToast,
    errorToast,
    onSave,
    onClose,
}: {
    title: string
    initialName: string
    initialDescription: string
    initialColor: string
    initialIcon: string
    icons: typeof ACCOUNT_ICONS | typeof CATEGORY_ICONS
    savedToast: string
    errorToast: string | ((error: unknown) => string)
    onSave: (value: {
        name: string
        description: string | undefined
        color: string
        icon: string
    }) => Promise<unknown>
    onClose: () => void
}) {
    const t = useT()
    const formId = useId()
    const [name, setName] = useState(initialName)
    const [description, setDescription] = useState(initialDescription)
    const [color, setColor] = useState(initialColor)
    const [icon, setIcon] = useState(initialIcon)
    const [saving, setSaving] = useState(false)

    const handleSubmit = async (event: FormEvent) => {
        event.preventDefault()
        const nextDescription = description.trim()
        setSaving(true)
        const promise = onSave({
            name: name.trim(),
            description:
                nextDescription !== initialDescription
                    ? nextDescription
                    : undefined,
            color,
            icon,
        })
        toast.promise(promise, {
            loading: t.common.saving,
            success: savedToast,
            error: errorToast,
        })
        try {
            await promise
            onClose()
        } catch {
            // toast.promise owns the user-facing error state.
        } finally {
            setSaving(false)
        }
    }

    return (
        <>
            <SheetHeader>
                <SheetTitle>{title}</SheetTitle>
            </SheetHeader>
            <form
                id={formId}
                onSubmit={handleSubmit}
                className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-4 py-2"
            >
                <EditField label={t.common.name} id={`${formId}-name`}>
                    <Input
                        id={`${formId}-name`}
                        value={name}
                        onChange={(event) => setName(event.target.value)}
                        required
                    />
                </EditField>
                <EditField
                    label={t.common.description}
                    id={`${formId}-description`}
                >
                    <Textarea
                        id={`${formId}-description`}
                        value={description}
                        onChange={(event) => setDescription(event.target.value)}
                        rows={3}
                    />
                </EditField>
                <VisualIdentityFields
                    color={color}
                    onColorChange={setColor}
                    icon={icon}
                    onIconChange={setIcon}
                    icons={icons}
                />
            </form>
            <ActionSheetFooter
                formId={formId}
                saving={saving}
                onClose={onClose}
            />
        </>
    )
}

type TagDoc = {
    id: string
    name: string
    description?: string | null
    color?: string
    parentId?: string
}

function TagActionWidget({
    entityId,
    wasUpdated,
}: {
    entityId: string
    wasUpdated: boolean
}) {
    const t = useT()
    const tag = useQuery(api.v1.tags.queries.get, { id: entityId })
    const [editOpen, setEditOpen] = useState(false)
    if (tag === undefined) return <ActionSkeleton />
    if (tag === null) return null

    const accent = normalizeTagColor(tag.color)
    return (
        <>
            <ActionCard>
                <EntityIcon color={accent}>
                    <Icon
                        name="sell"
                        filled
                        size={16}
                        style={{ color: accent }}
                    />
                </EntityIcon>
                <ActionCopy
                    title={tag.name}
                    detail={t.actionWidget.tagDetail({ updated: wasUpdated })}
                />
                <EditButton onClick={() => setEditOpen(true)} />
            </ActionCard>
            <ActionSheet
                open={editOpen}
                onOpenChange={setEditOpen}
                title={t.actionWidget.editTag}
            >
                <TagEditContent tag={tag} onClose={() => setEditOpen(false)} />
            </ActionSheet>
        </>
    )
}

function TagEditContent({
    tag,
    onClose,
}: {
    tag: TagDoc
    onClose: () => void
}) {
    const t = useT()
    const updateTag = useMutation(api.v1.tags.mutations.update)
    const tags = useQuery(api.v1.tags.queries.listActive)
    const formId = useId()
    const [name, setName] = useState(tag.name)
    const [description, setDescription] = useState(tag.description ?? '')
    const [color, setColor] = useState(() => normalizeTagColor(tag.color))
    const [parentId, setParentId] = useState(tag.parentId ?? '')
    const [saving, setSaving] = useState(false)

    const invalidParents = tags ? descendantTagIds(tags, tag.id) : new Set()
    invalidParents.add(tag.id)
    const parentOptions = tags?.filter((item) => !invalidParents.has(item.id))

    const handleSubmit = async (event: FormEvent) => {
        event.preventDefault()
        const nextDescription = description.trim()
        const originalParentId = tag.parentId ?? ''
        setSaving(true)
        const promise = updateTag({
            id: tag.id,
            name: name.trim(),
            description:
                nextDescription !== (tag.description ?? '')
                    ? nextDescription
                    : undefined,
            color,
            parentId:
                parentId !== originalParentId ? parentId || null : undefined,
        })
        toast.promise(promise, {
            loading: t.common.saving,
            success: t.actionWidget.tagSaved,
            error: t.common.saveFailed,
        })
        try {
            await promise
            onClose()
        } catch {
            // toast.promise owns the user-facing error state.
        } finally {
            setSaving(false)
        }
    }

    return (
        <>
            <SheetHeader>
                <SheetTitle>{t.actionWidget.editTag}</SheetTitle>
            </SheetHeader>
            <form
                id={formId}
                onSubmit={handleSubmit}
                className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-4 py-2"
            >
                <EditField label={t.common.name} id={`${formId}-name`}>
                    <Input
                        id={`${formId}-name`}
                        value={name}
                        onChange={(event) => setName(event.target.value)}
                        required
                    />
                </EditField>
                <EditField
                    label={t.actionWidget.parentTag}
                    id={`${formId}-parent`}
                >
                    <Select
                        id={`${formId}-parent`}
                        aria-label={t.actionWidget.parentTag}
                        variant="outlined"
                        className="w-full"
                        isDisabled={tags === undefined}
                        selectedKey={parentId === '' ? NO_PARENT : parentId}
                        onSelectionChange={(key) =>
                            setParentId(key === NO_PARENT ? '' : String(key))
                        }
                    >
                        {[
                            <SelectOption key={NO_PARENT}>
                                {t.actionWidget.noParentTag}
                            </SelectOption>,
                            ...(parentOptions ?? []).map((item) => (
                                <SelectOption key={item.id}>
                                    {item.name}
                                </SelectOption>
                            )),
                        ]}
                    </Select>
                </EditField>
                <EditField
                    label={t.common.description}
                    id={`${formId}-description`}
                >
                    <Textarea
                        id={`${formId}-description`}
                        value={description}
                        onChange={(event) => setDescription(event.target.value)}
                        rows={3}
                    />
                </EditField>
                <div className="flex flex-col gap-2">
                    <Label>{t.common.color}</Label>
                    <ColorSwatches
                        value={color}
                        onChange={setColor}
                        options={COLOR_OPTIONS}
                    />
                </div>
            </form>
            <ActionSheetFooter
                formId={formId}
                saving={saving}
                onClose={onClose}
            />
        </>
    )
}

function ActionSheet({
    open,
    onOpenChange,
    title,
    children,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    title: string
    children: ReactNode
}) {
    // The native voice widget edits in a modal bottom sheet
    // (voice_action_widget.dart), not a side sheet.
    return (
        <BottomSheet open={open} onOpenChange={onOpenChange} title={title}>
            <div className="flex min-h-0 flex-1 flex-col">{children}</div>
        </BottomSheet>
    )
}

function ActionSheetFooter({
    formId,
    saving,
    onClose,
}: {
    formId: string
    saving: boolean
    onClose: () => void
}) {
    const t = useT()
    return (
        <SheetFooter className="pb-[max(1rem,env(safe-area-inset-bottom))]">
            <Button
                type="button"
                variant="outline"
                onClick={onClose}
                disabled={saving}
            >
                {t.common.cancel}
            </Button>
            <Button type="submit" form={formId} disabled={saving}>
                {saving ? t.common.saving : t.common.save}
            </Button>
        </SheetFooter>
    )
}

function ActionCard({ children }: { children: ReactNode }) {
    return (
        <div className="flex justify-center">
            <div className="flex w-full max-w-[92%] items-center gap-3 rounded-lg border bg-card px-3 py-2.5 text-sm">
                {children}
            </div>
        </div>
    )
}

function ActionCopy({ title, detail }: { title: string; detail: string }) {
    return (
        <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium">{title}</p>
            <p className="truncate text-xs text-muted-foreground">{detail}</p>
        </div>
    )
}

function EditButton({ onClick }: { onClick: () => void }) {
    const t = useT()
    return (
        <Button
            type="button"
            variant="ghost"
            size="sm"
            className="shrink-0 gap-1.5"
            onClick={onClick}
        >
            <Icon name="edit" size={14} />
            {t.common.edit}
        </Button>
    )
}

function EntityIcon({
    color,
    children,
}: {
    color: string
    children: ReactNode
}) {
    return (
        <span
            className="flex size-7 shrink-0 items-center justify-center rounded-full"
            style={{ backgroundColor: `${color}24` }}
        >
            {children}
        </span>
    )
}

function ActionSkeleton() {
    return (
        <div className="flex justify-center">
            <div className="flex w-full max-w-[92%] items-center gap-3 rounded-lg border bg-card px-3 py-2.5">
                <Skeleton className="size-7 rounded-full" />
                <div className="flex-1 space-y-1.5">
                    <Skeleton className="h-3 w-32" />
                    <Skeleton className="h-3 w-48" />
                </div>
            </div>
        </div>
    )
}

function EditField({
    label,
    id,
    children,
}: {
    label: string
    id: string
    children: ReactNode
}) {
    return (
        <div className="flex flex-col gap-1.5">
            <Label htmlFor={id}>{label}</Label>
            {children}
        </div>
    )
}

function VisualIdentityFields({
    color,
    onColorChange,
    icon,
    onIconChange,
    icons,
}: {
    color: string
    onColorChange: (color: string) => void
    icon: string
    onIconChange: (icon: string) => void
    icons: typeof ACCOUNT_ICONS | typeof CATEGORY_ICONS
}) {
    const t = useT()
    return (
        <>
            <div className="flex flex-col gap-2">
                <Label>{t.common.color}</Label>
                <ColorSwatches
                    value={color}
                    onChange={onColorChange}
                    options={COLOR_OPTIONS}
                    themed
                />
            </div>
            <div className="flex flex-col gap-2">
                <Label>{t.common.icon}</Label>
                <IconPicker
                    icon={icon}
                    color={color}
                    onIconChange={onIconChange}
                    icons={icons}
                />
            </div>
        </>
    )
}

function txnTypeConfig(type: TxnType, t: Messages) {
    switch (type) {
        case 'expense':
            return {
                icon: 'arrow_downward',
                iconCls: {
                    bg: 'bg-red-100 dark:bg-red-900/30',
                    text: 'text-red-600 dark:text-red-400',
                },
                label: t.actionWidget.expense,
            }
        case 'income':
            return {
                icon: 'arrow_upward',
                iconCls: {
                    bg: 'bg-green-100 dark:bg-green-900/30',
                    text: 'text-green-600 dark:text-green-400',
                },
                label: t.actionWidget.income,
            }
        case 'transfer':
            return {
                icon: 'swap_horiz',
                iconCls: {
                    bg: 'bg-blue-100 dark:bg-blue-900/30',
                    text: 'text-blue-600 dark:text-blue-400',
                },
                label: t.actionWidget.transfer,
            }
        case 'balance_adjustment':
            return {
                icon: 'balance',
                iconCls: {
                    bg: 'bg-amber-100 dark:bg-amber-900/30',
                    text: 'text-amber-700 dark:text-amber-400',
                },
                label: t.actionWidget.balanceAdjustment,
            }
    }
}

function epochToNumericDate(epoch: bigint, locale: string): string {
    return new Intl.DateTimeFormat(locale).format(new Date(Number(epoch)))
}

function epochToHHMM(epoch: bigint, locale: string): string {
    return new Intl.DateTimeFormat(locale, {
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
    }).format(new Date(Number(epoch)))
}

function centsToDecimalStr(cents: bigint): string {
    const sign = cents < 0n ? '-' : ''
    const absolute = cents < 0n ? -cents : cents
    return `${sign}${absolute / 100n}.${String(absolute % 100n).padStart(2, '0')}`
}

function formatAmount(cents: bigint, currency: string): string {
    return `${centsToDecimalStr(cents)} ${currency}`
}

function descendantTagIds(
    tags: Array<{ id: string; parentId?: string }>,
    rootId: string,
): Set<string> {
    const descendants = new Set<string>()
    const queue = [rootId]
    while (queue.length > 0) {
        const parentId = queue.shift()
        for (const tag of tags) {
            if (tag.parentId === parentId && !descendants.has(tag.id)) {
                descendants.add(tag.id)
                queue.push(tag.id)
            }
        }
    }
    return descendants
}

function assertNever(value: never): null {
    console.error(`Unsupported editable tool: ${String(value)}`)
    return null
}
