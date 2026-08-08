import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { Check, Pencil, Trash2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { CategoryIcon } from '@/components/category-icon'
import { ColorSwatches } from '@/components/color-swatches'
import { EntityRecentTransactions } from '@/components/entity-recent-transactions'
import { IconPicker } from '@/components/icon-picker'
import { MonthlySpend } from '@/components/monthly-spend'
import { Button } from '@/components/ui/button'
import {
    Dialog,
    DialogContent,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet'
import { CATEGORY_ICONS } from '@/lib/category-icons'
import {
    CATEGORY_DEFAULT_COLOR,
    COLOR_OPTIONS,
    normalizeColor,
} from '@/lib/entity-colors'
import { useT } from '@/lib/i18n'

export type CategorySummary = {
    id: string
    name: string
    icon?: string
    color?: string
    description?: string
}

export function CategoryDetailsSheet({
    category,
    open,
    onOpenChange,
}: {
    category: CategorySummary | null
    open: boolean
    onOpenChange: (open: boolean) => void
}) {
    const navigate = useNavigate()
    const t = useT()
    const updateCategory = useMutation(api.v1.categories.mutations.update)
    const archiveCategory = useMutation(api.v1.categories.mutations.archive)

    const categoryId = category?.id ?? ''
    const [monthWindow] = useState(() => {
        const now = new Date()
        const from = new Date(now.getFullYear(), now.getMonth(), 1)
        const to = new Date(now.getFullYear(), now.getMonth() + 1, 1)
        return {
            fromMs: BigInt(from.getTime()),
            toExclusiveMs: BigInt(to.getTime()),
        }
    })

    const spend = useQuery(
        api.v1.categories.queries.spendByCurrency,
        category ? { id: categoryId, ...monthWindow } : 'skip',
    )
    const recent = useQuery(
        api.v1.categories.queries.recentTransactions,
        category ? { id: categoryId, limit: 5 } : 'skip',
    )

    const [editing, setEditing] = useState(false)
    const [saving, setSaving] = useState(false)
    const [name, setName] = useState('')
    const [color, setColor] = useState(CATEGORY_DEFAULT_COLOR)
    const [icon, setIcon] = useState('category')
    const [deleteOpen, setDeleteOpen] = useState(false)

    // Re-seed the editable identity only when a *different* category opens.
    // Keying on the id (not the object) keeps live query updates — e.g. the
    // refreshed values right after a save — from clobbering in-progress edits.
    const [seededId, setSeededId] = useState<string | null>(null)
    useEffect(() => {
        const id = category?.id ?? null
        if (id === seededId) return
        setSeededId(id)
        if (category) {
            setName(category.name)
            setColor(normalizeColor(category.color, CATEGORY_DEFAULT_COLOR))
            setIcon(category.icon ?? 'category')
            setEditing(false)
        }
    }, [category, seededId])

    if (!category) return null

    const accent = editing
        ? color
        : normalizeColor(category.color, CATEGORY_DEFAULT_COLOR)

    const handleToggleEditing = async () => {
        if (!editing) {
            setEditing(true)
            return
        }
        const trimmed = name.trim()
        if (!trimmed) {
            toast.error(t.common.nameCannotBeEmpty)
            return
        }
        setSaving(true)
        const promise = updateCategory({
            id: category.id,
            name: trimmed,
            color,
            icon,
        })
        toast.promise(promise, {
            loading: t.insights.categorySaving,
            success: t.insights.categorySaved,
            error: t.insights.categorySaveFailed,
        })
        try {
            await promise
            setEditing(false)
        } finally {
            setSaving(false)
        }
    }

    const handleDelete = async () => {
        setSaving(true)
        const promise = archiveCategory({ id: category.id })
        toast.promise(promise, {
            loading: t.insights.categoryDeleting,
            success: t.insights.categoryDeleted,
            error: t.insights.categoryDeleteFailed,
        })
        try {
            await promise
            setDeleteOpen(false)
            onOpenChange(false)
        } finally {
            setSaving(false)
        }
    }

    const viewAllTransactions = () => {
        onOpenChange(false)
        navigate('/activity', { state: { categoryIds: [category.id] } })
    }

    return (
        <Sheet open={open} onOpenChange={onOpenChange}>
            <SheetContent side="right" className="w-full gap-0 p-0 sm:max-w-md">
                <SheetTitle className="sr-only">{category.name}</SheetTitle>
                <div className="flex flex-1 flex-col gap-3 overflow-y-auto p-4">
                    {/* Identity hero. */}
                    <div
                        className="flex items-center gap-4 rounded-2xl p-5"
                        style={{ backgroundColor: `${accent}24` }}
                    >
                        {editing ? (
                            <IconPicker
                                icon={icon}
                                color={color}
                                onIconChange={setIcon}
                                icons={CATEGORY_ICONS}
                            />
                        ) : (
                            <span
                                className="flex size-14 shrink-0 items-center justify-center rounded-2xl"
                                style={{ backgroundColor: `${accent}47` }}
                            >
                                <CategoryIcon
                                    name={category.icon}
                                    className="size-7"
                                    color={accent}
                                />
                            </span>
                        )}
                        {editing ? (
                            <Input
                                value={name}
                                onChange={(e) => setName(e.target.value)}
                                className="bg-background"
                                aria-label={t.common.name}
                            />
                        ) : (
                            <div className="flex min-w-0 flex-1 flex-col">
                                <span className="truncate text-xl font-semibold">
                                    {category.name}
                                </span>
                                {category.description ? (
                                    <span className="truncate text-sm text-muted-foreground">
                                        {category.description}
                                    </span>
                                ) : null}
                            </div>
                        )}
                    </div>

                    {editing ? (
                        <ColorSwatches
                            value={color}
                            onChange={setColor}
                            options={COLOR_OPTIONS}
                        />
                    ) : null}

                    {/* Monthly spend hero. */}
                    <div className="flex flex-col gap-1 rounded-2xl border bg-card p-5">
                        <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                            {t.insights.spentThisMonth}
                        </span>
                        <MonthlySpend spend={spend} />
                    </div>

                    {/* Actions. */}
                    <div className="flex items-center gap-2">
                        <Button
                            variant={editing ? 'default' : 'secondary'}
                            className="flex-1"
                            onClick={handleToggleEditing}
                            disabled={saving}
                        >
                            {editing ? (
                                <Check data-icon="inline-start" />
                            ) : (
                                <Pencil data-icon="inline-start" />
                            )}
                            {editing ? t.common.done : t.common.edit}
                        </Button>
                        <Button
                            variant="destructive"
                            size="icon"
                            onClick={() => setDeleteOpen(true)}
                            disabled={saving}
                            aria-label={t.common.delete}
                        >
                            <Trash2 />
                        </Button>
                    </div>

                    <EntityRecentTransactions
                        title={t.insights.lastMovements}
                        viewAllLabel={t.insights.viewAll}
                        onViewAll={viewAllTransactions}
                        transactions={recent}
                    />
                </div>
            </SheetContent>

            <Dialog open={deleteOpen} onOpenChange={setDeleteOpen}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>
                            {t.insights.categoryDeleteTitle}
                        </DialogTitle>
                    </DialogHeader>
                    <p className="text-sm text-muted-foreground">
                        {t.insights.categoryDeleteConfirm({
                            name: category.name,
                        })}
                    </p>
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setDeleteOpen(false)}
                            disabled={saving}
                        >
                            {t.common.cancel}
                        </Button>
                        <Button
                            variant="destructive"
                            onClick={handleDelete}
                            disabled={saving}
                        >
                            {t.common.delete}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </Sheet>
    )
}
