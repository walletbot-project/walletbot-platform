import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useMutation } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { MoreHorizontal, Tag } from 'lucide-react'
import { useState } from 'react'
import { toast } from 'sonner'
import { ConfirmDialog } from '@/components/shared/confirm-dialog'
import { EmptyState } from '@/components/shared/empty-state'
import { ListSkeleton } from '@/components/shared/loading-skeleton'
import { Button } from '@/components/ui/button'
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { useTags } from '@/hooks/use-tags'
import { TagFormDialog } from './tag-form-dialog'

type TagItem = FunctionReturnType<typeof api.tags.queries.listTags>[number]

export function TagList() {
    const { tags, isLoading } = useTags()
    const deleteTag = useMutation(api.tags.mutations.deleteTag)
    const [editTag, setEditTag] = useState<TagItem | null>(null)
    const [deleteTarget, setDeleteTarget] = useState<TagItem | null>(null)

    if (isLoading) return <ListSkeleton count={4} />

    if (tags.length === 0) {
        return <EmptyState icon={Tag} title={t('tags.empty')} />
    }

    return (
        <>
            <div className="flex flex-col gap-2">
                {tags.map((tag) => (
                    <div
                        key={tag._id}
                        className="flex items-center gap-3 rounded-lg border p-3"
                    >
                        <div
                            className="size-3 shrink-0 rounded-full"
                            style={{ backgroundColor: tag.color }}
                        />
                        <span className="flex-1 text-sm font-medium">
                            {tag.name}
                        </span>
                        <DropdownMenu>
                            <DropdownMenuTrigger
                                render={
                                    <Button variant="ghost" size="icon-xs" />
                                }
                            >
                                <MoreHorizontal className="size-4" />
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                                <DropdownMenuItem
                                    onClick={() => setEditTag(tag)}
                                >
                                    {t('common.edit')}
                                </DropdownMenuItem>
                                <DropdownMenuItem
                                    className="text-destructive"
                                    onClick={() => setDeleteTarget(tag)}
                                >
                                    {t('common.delete')}
                                </DropdownMenuItem>
                            </DropdownMenuContent>
                        </DropdownMenu>
                    </div>
                ))}
            </div>

            <TagFormDialog
                open={editTag !== null}
                onOpenChange={(open) => !open && setEditTag(null)}
                tag={editTag ?? undefined}
            />

            <ConfirmDialog
                open={deleteTarget !== null}
                onOpenChange={(open) => !open && setDeleteTarget(null)}
                title={t('tags.delete')}
                description={t('tags.delete.confirm')}
                confirmLabel={t('common.delete')}
                onConfirm={async () => {
                    if (!deleteTarget) return
                    try {
                        await deleteTag({ tagId: deleteTarget._id })
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
