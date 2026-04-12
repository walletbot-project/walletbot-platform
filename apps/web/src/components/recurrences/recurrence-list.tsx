import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useMutation, useQuery } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { MoreHorizontal, Repeat } from 'lucide-react'
import { useState } from 'react'
import { toast } from 'sonner'
import { ConfirmDialog } from '@/components/shared/confirm-dialog'
import { CurrencyDisplay } from '@/components/shared/currency-display'
import { EmptyState } from '@/components/shared/empty-state'
import { ListSkeleton } from '@/components/shared/loading-skeleton'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { frequencyLabel, TX_TYPE_ICONS, txTypeColor } from '@/lib/format'
import { cn } from '@/lib/utils'
import { RecurrenceFormDialog } from './recurrence-form-dialog'

type Recurrence = FunctionReturnType<
    typeof api.recurrences.queries.listRecurrences
>[number]

export function RecurrenceList() {
    const recurrences = useQuery(api.recurrences.queries.listRecurrences)
    const updateRecurrence = useMutation(
        api.recurrences.mutations.updateRecurrence,
    )
    const deleteRecurrence = useMutation(
        api.recurrences.mutations.deleteRecurrence,
    )
    const [editItem, setEditItem] = useState<Recurrence | null>(null)
    const [deleteItem, setDeleteItem] = useState<Recurrence | null>(null)

    if (recurrences === undefined) return <ListSkeleton count={3} />

    if (recurrences.length === 0) {
        return (
            <EmptyState
                icon={Repeat}
                title="No recurring transactions"
                description="Set up recurring expenses or income to track them automatically."
            />
        )
    }

    return (
        <>
            <div className="flex flex-col gap-2">
                {recurrences.map((rec) => {
                    const Icon = TX_TYPE_ICONS[rec.type]
                    return (
                        <div
                            key={rec._id}
                            className={cn(
                                'flex items-center gap-3 rounded-lg border p-3',
                                !rec.isActive && 'opacity-50',
                            )}
                        >
                            <div
                                className={cn(
                                    'flex size-8 shrink-0 items-center justify-center rounded-full',
                                    rec.type === 'expense'
                                        ? 'bg-red-100 dark:bg-red-900/30'
                                        : rec.type === 'income'
                                          ? 'bg-green-100 dark:bg-green-900/30'
                                          : 'bg-blue-100 dark:bg-blue-900/30',
                                )}
                            >
                                <Icon
                                    className={cn(
                                        'size-4',
                                        txTypeColor(rec.type),
                                    )}
                                />
                            </div>
                            <div className="flex-1">
                                <div className="flex items-center gap-2">
                                    <span className="text-sm font-medium">
                                        {rec.description}
                                    </span>
                                    <Badge
                                        variant={
                                            rec.isActive
                                                ? 'secondary'
                                                : 'outline'
                                        }
                                        className="text-[10px]"
                                    >
                                        {rec.isActive ? 'Active' : 'Paused'}
                                    </Badge>
                                </div>
                                <span className="text-xs text-muted-foreground">
                                    {frequencyLabel(
                                        rec.frequency,
                                        rec.interval,
                                    )}
                                </span>
                            </div>
                            <CurrencyDisplay
                                cents={rec.amount}
                                currency={rec.currency}
                                className={cn(
                                    'text-sm font-semibold',
                                    txTypeColor(rec.type),
                                )}
                            />
                            <DropdownMenu>
                                <DropdownMenuTrigger
                                    render={
                                        <Button
                                            variant="ghost"
                                            size="icon-xs"
                                        />
                                    }
                                >
                                    <MoreHorizontal className="size-4" />
                                </DropdownMenuTrigger>
                                <DropdownMenuContent align="end">
                                    <DropdownMenuItem
                                        onClick={() => setEditItem(rec)}
                                    >
                                        {t('common.edit')}
                                    </DropdownMenuItem>
                                    <DropdownMenuItem
                                        onClick={async () => {
                                            await updateRecurrence({
                                                recurrenceId: rec._id,
                                                isActive: !rec.isActive,
                                            })
                                            toast.success(
                                                t('toast.success.updated'),
                                            )
                                        }}
                                    >
                                        {rec.isActive ? 'Pause' : 'Resume'}
                                    </DropdownMenuItem>
                                    <DropdownMenuItem
                                        className="text-destructive"
                                        onClick={() => setDeleteItem(rec)}
                                    >
                                        {t('common.delete')}
                                    </DropdownMenuItem>
                                </DropdownMenuContent>
                            </DropdownMenu>
                        </div>
                    )
                })}
            </div>

            <RecurrenceFormDialog
                open={editItem !== null}
                onOpenChange={(open) => !open && setEditItem(null)}
                recurrence={editItem ?? undefined}
            />

            <ConfirmDialog
                open={deleteItem !== null}
                onOpenChange={(open) => !open && setDeleteItem(null)}
                title="Delete Recurring Transaction"
                description="Are you sure? Future transactions will no longer be generated."
                confirmLabel={t('common.delete')}
                onConfirm={async () => {
                    if (!deleteItem) return
                    try {
                        await deleteRecurrence({
                            recurrenceId: deleteItem._id,
                        })
                        toast.success(t('toast.success.deleted'))
                    } catch (err) {
                        toast.error(
                            err instanceof Error
                                ? err.message
                                : t('toast.error.generic'),
                        )
                    }
                }}
            />
        </>
    )
}
