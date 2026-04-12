import { api } from '@wallet-bot/backend/api'
import { type TranslationKey, t } from '@wallet-bot/shared'
import { useMutation } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { ChevronRight, Grid3x3, Lock, MoreHorizontal } from 'lucide-react'
import { useState } from 'react'
import { toast } from 'sonner'
import { ConfirmDialog } from '@/components/shared/confirm-dialog'
import { EmptyState } from '@/components/shared/empty-state'
import { ListSkeleton } from '@/components/shared/loading-skeleton'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
    Collapsible,
    CollapsibleContent,
    CollapsibleTrigger,
} from '@/components/ui/collapsible'
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { useCategories } from '@/hooks/use-categories'
import { CategoryFormDialog } from './category-form-dialog'

type Category = FunctionReturnType<
    typeof api.categories.queries.listCategories
>[number]
type AnyCategory = Category | Category['children'][number]

export function CategoryTree() {
    const { categories, isLoading } = useCategories()
    const deleteCategory = useMutation(api.categories.mutations.deleteCategory)
    const [editCat, setEditCat] = useState<AnyCategory | null>(null)
    const [deleteCat, setDeleteCat] = useState<AnyCategory | null>(null)

    if (isLoading) return <ListSkeleton count={6} />

    if (categories.length === 0) {
        return <EmptyState icon={Grid3x3} title={t('categories.empty')} />
    }

    return (
        <>
            <div className="flex flex-col gap-1">
                {categories.map((cat) => (
                    <Collapsible key={cat._id}>
                        <div className="flex items-center gap-2 rounded-lg border p-3">
                            {cat.children.length > 0 && (
                                <CollapsibleTrigger
                                    render={
                                        <Button
                                            variant="ghost"
                                            size="icon-xs"
                                        />
                                    }
                                >
                                    <ChevronRight className="size-3.5 transition-transform [[data-state=open]>&]:rotate-90" />
                                </CollapsibleTrigger>
                            )}
                            {cat.children.length === 0 && (
                                <div className="size-6" />
                            )}
                            <div
                                className="size-3 rounded-full shrink-0"
                                style={{ backgroundColor: cat.color }}
                            />
                            <span className="text-base">{cat.icon}</span>
                            <span className="flex-1 text-sm font-medium">
                                {cat.isSystem
                                    ? t(cat.name as TranslationKey)
                                    : cat.name}
                            </span>
                            {cat.isSystem && (
                                <Lock className="size-3 text-muted-foreground" />
                            )}
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
                                        onClick={() => setEditCat(cat)}
                                    >
                                        {t('common.edit')}
                                    </DropdownMenuItem>
                                    {!cat.isSystem && (
                                        <DropdownMenuItem
                                            className="text-destructive"
                                            onClick={() => setDeleteCat(cat)}
                                        >
                                            {t('common.delete')}
                                        </DropdownMenuItem>
                                    )}
                                </DropdownMenuContent>
                            </DropdownMenu>
                        </div>
                        {cat.children.length > 0 && (
                            <CollapsibleContent>
                                <div className="ml-8 flex flex-col gap-1 pt-1">
                                    {cat.children.map((child) => (
                                        <div
                                            key={child._id}
                                            className="flex items-center gap-2 rounded-lg border p-2.5"
                                        >
                                            <div
                                                className="size-2.5 rounded-full shrink-0"
                                                style={{
                                                    backgroundColor:
                                                        child.color,
                                                }}
                                            />
                                            <span className="text-sm">
                                                {child.icon}
                                            </span>
                                            <span className="flex-1 text-sm">
                                                {child.isSystem
                                                    ? t(
                                                          child.name as TranslationKey,
                                                      )
                                                    : child.name}
                                            </span>
                                            {child.isSystem && (
                                                <Badge
                                                    variant="secondary"
                                                    className="text-[10px]"
                                                >
                                                    system
                                                </Badge>
                                            )}
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
                                                        onClick={() =>
                                                            setEditCat(child)
                                                        }
                                                    >
                                                        {t('common.edit')}
                                                    </DropdownMenuItem>
                                                    {!child.isSystem && (
                                                        <DropdownMenuItem
                                                            className="text-destructive"
                                                            onClick={() =>
                                                                setDeleteCat(
                                                                    child,
                                                                )
                                                            }
                                                        >
                                                            {t('common.delete')}
                                                        </DropdownMenuItem>
                                                    )}
                                                </DropdownMenuContent>
                                            </DropdownMenu>
                                        </div>
                                    ))}
                                </div>
                            </CollapsibleContent>
                        )}
                    </Collapsible>
                ))}
            </div>

            <CategoryFormDialog
                open={editCat !== null}
                onOpenChange={(open) => !open && setEditCat(null)}
                category={editCat ?? undefined}
            />

            <ConfirmDialog
                open={deleteCat !== null}
                onOpenChange={(open) => !open && setDeleteCat(null)}
                title={t('categories.delete')}
                description={t('categories.delete.confirm')}
                confirmLabel={t('common.delete')}
                onConfirm={async () => {
                    if (!deleteCat) return
                    try {
                        await deleteCategory({ categoryId: deleteCat._id })
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
