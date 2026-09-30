import {
    type Announcements,
    closestCenter,
    DndContext,
    type DragEndEvent,
    type KeyboardCoordinateGetter,
    KeyboardSensor,
    PointerSensor,
    type UniqueIdentifier,
    useSensor,
    useSensors,
} from '@dnd-kit/core'
import {
    arrayMove,
    SortableContext,
    sortableKeyboardCoordinates,
    useSortable,
    verticalListSortingStrategy,
} from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { type CSSProperties, type ReactNode, useRef } from 'react'
import { Icon } from '@/components/m3/icon'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'

type SortableListProps<T> = {
    items: readonly T[]
    idOf: (item: T) => string
    /** The item's visible name, for its handle label and announcements. */
    nameOf: (item: T) => string
    /** Reorder mode: rows show a drag handle and stop opening on click. */
    editing: boolean
    /** Called with every id in the new order after a drop that moved one. */
    onReorder: (ids: string[]) => void
    renderItem: (
        item: T,
        slot: {
            /** Shape for the row's place in the group (fully round while lifted). */
            radius: CSSProperties
            /** The drag handle while editing; `undefined` otherwise. */
            dragHandle: ReactNode
        },
    ) => ReactNode
    className?: string
    /** Gap between rows, in px. Defaults to the grouped-list seam. */
    gap?: number
    /**
     * Classes for the row while it is lifted. Rows that paint their own card
     * only need the shadow; content without a surface (tag chips) also needs
     * a background to read as picked up.
     */
    liftedClassName?: string
}

/**
 * A grouped list the user reorders while in edit mode: each row grows a drag
 * handle that moves it with the pointer, or with the keyboard (space to pick
 * up, arrows to move, space to drop, escape to cancel). The web counterpart of
 * native's long-press `ReorderableGroupedList`.
 *
 * One tree in both modes (LESSONS.md #14): toggling `editing` only disables
 * the sortable rows, it never swaps the list for another element.
 */
export function SortableList<T>({
    items,
    idOf,
    nameOf,
    editing,
    onReorder,
    renderItem,
    className,
    gap = GROUP_SPACING,
    liftedClassName = 'shadow-lg',
}: SortableListProps<T>) {
    const t = useT()
    const ids = items.map(idOf)
    // Arrow keys step to the previous/next row by lining up the row's centre
    // with its neighbour's. dnd-kit's `sortableKeyboardCoordinates` aligns
    // edges instead, which with rows of different heights (a tag family is
    // taller than a single tag) leaves the lifted row closest to its own slot,
    // so it never moves.
    const coordinateGetter: KeyboardCoordinateGetter = (event, args) => {
        const step =
            event.code === 'ArrowDown' ? 1 : event.code === 'ArrowUp' ? -1 : 0
        if (step === 0) return sortableKeyboardCoordinates(event, args)
        event.preventDefault()
        const { active, over, collisionRect, droppableRects } = args.context
        if (!active || !collisionRect) return undefined
        const from = ids.indexOf(String(over?.id ?? active.id))
        const target = ids[from + step]
        const rect =
            target === undefined ? undefined : droppableRects.get(target)
        if (!rect) return undefined
        const shift =
            rect.top +
            rect.height / 2 -
            (collisionRect.top + collisionRect.height / 2)
        return {
            ...args.currentCoordinates,
            y: args.currentCoordinates.y + shift,
        }
    }
    const sensors = useSensors(
        useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
        useSensor(KeyboardSensor, { coordinateGetter }),
    )

    const nameFor = (id: UniqueIdentifier) => {
        const item = items.find((candidate) => idOf(candidate) === String(id))
        return item ? nameOf(item) : ''
    }
    const positionOf = (id: UniqueIdentifier) => ids.indexOf(String(id)) + 1
    // dnd-kit reports the row as "over" itself right after pick-up, which
    // would replace the pick-up announcement before a screen reader reads it.
    // Announce a move only when the target actually changes.
    const lastOverId = useRef<UniqueIdentifier | null>(null)
    const announcements: Announcements = {
        onDragStart: ({ active }) => {
            lastOverId.current = active.id
            return t.reorder.picked({
                name: nameFor(active.id),
                position: positionOf(active.id),
                total: ids.length,
            })
        },
        onDragOver: ({ active, over }) => {
            if (!over || over.id === lastOverId.current) return undefined
            lastOverId.current = over.id
            return t.reorder.moved({
                name: nameFor(active.id),
                position: positionOf(over.id),
                total: ids.length,
            })
        },
        onDragEnd: ({ active, over }) =>
            over
                ? t.reorder.dropped({
                      name: nameFor(active.id),
                      position: positionOf(over.id),
                      total: ids.length,
                  })
                : t.reorder.cancelled({ name: nameFor(active.id) }),
        onDragCancel: ({ active }) =>
            t.reorder.cancelled({ name: nameFor(active.id) }),
    }

    const handleDragEnd = ({ active, over }: DragEndEvent) => {
        if (!over || active.id === over.id) return
        const from = ids.indexOf(String(active.id))
        const to = ids.indexOf(String(over.id))
        if (from < 0 || to < 0) return
        onReorder(arrayMove(ids, from, to))
    }

    return (
        <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            onDragEnd={handleDragEnd}
            accessibility={{
                announcements,
                screenReaderInstructions: {
                    draggable: t.reorder.instructions,
                },
            }}
        >
            <SortableContext
                items={ids}
                strategy={verticalListSortingStrategy}
                disabled={!editing}
            >
                <div className={cn('flex flex-col', className)} style={{ gap }}>
                    {items.map((item, index) => (
                        <SortableRow
                            key={idOf(item)}
                            id={idOf(item)}
                            name={nameOf(item)}
                            editing={editing}
                            radius={groupedRadius(index, items.length)}
                            liftedClassName={liftedClassName}
                            render={(slot) => renderItem(item, slot)}
                        />
                    ))}
                </div>
            </SortableContext>
        </DndContext>
    )
}

function SortableRow({
    id,
    name,
    editing,
    radius,
    liftedClassName,
    render,
}: {
    id: string
    name: string
    editing: boolean
    radius: CSSProperties
    liftedClassName: string
    render: (slot: {
        radius: CSSProperties
        dragHandle: ReactNode
    }) => ReactNode
}) {
    const t = useT()
    const {
        attributes,
        listeners,
        setNodeRef,
        setActivatorNodeRef,
        transform,
        transition,
        isDragging,
    } = useSortable({
        id,
        attributes: { roleDescription: t.reorder.roleDescription },
    })
    const lifted = groupedRadius(0, 1)

    return (
        <div
            ref={setNodeRef}
            className={cn(
                'relative',
                isDragging && 'z-10',
                isDragging && liftedClassName,
            )}
            style={{
                transform: CSS.Translate.toString(transform),
                transition,
                ...(isDragging ? lifted : radius),
            }}
        >
            {render({
                radius: isDragging ? lifted : radius,
                dragHandle: editing ? (
                    <button
                        type="button"
                        ref={setActivatorNodeRef}
                        {...attributes}
                        {...listeners}
                        aria-label={t.reorder.dragHandle({ name })}
                        className={cn(
                            'm3-state-layer -my-2 -mr-2 flex size-10 shrink-0 touch-none items-center justify-center rounded-full text-on-surface-variant focus-visible:outline-2 focus-visible:outline-offset-2',
                            isDragging ? 'cursor-grabbing' : 'cursor-grab',
                        )}
                    >
                        <Icon name="drag_indicator" />
                    </button>
                ) : undefined,
            })}
        </div>
    )
}
