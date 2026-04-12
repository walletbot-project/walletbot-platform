import { useMemo } from 'react'
import { Combobox } from '@/components/ui/combobox'
import { Skeleton } from '@/components/ui/skeleton'
import { useTags } from '@/hooks/use-tags'

interface TagSelectorProps {
    value: string[]
    onChange: (tagIds: string[]) => void
    disabled?: boolean
    className?: string
}

export function TagSelector({
    value,
    onChange,
    disabled,
    className,
}: TagSelectorProps) {
    const { tags, isLoading } = useTags()

    const options = useMemo(
        () =>
            tags.map((tag) => ({
                value: tag._id,
                label: tag.name,
            })),
        [tags],
    )

    if (isLoading) return <Skeleton className="h-8 w-full" />

    return (
        <Combobox
            value={value}
            onChange={onChange}
            multiple
            options={options}
            placeholder="Select tags..."
            emptyMessage="No tags"
            disabled={disabled}
            className={className}
        />
    )
}
