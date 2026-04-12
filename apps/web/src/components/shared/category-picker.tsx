import { type TranslationKey, t } from '@wallet-bot/shared'
import { useMemo } from 'react'
import { Combobox } from '@/components/ui/combobox'
import { Skeleton } from '@/components/ui/skeleton'
import { useCategories } from '@/hooks/use-categories'

interface CategoryPickerProps {
    value: string | undefined
    onChange: (categoryId: string | undefined) => void
    disabled?: boolean
    className?: string
}

function resolveCategoryName(name: string, isSystem: boolean): string {
    if (isSystem) {
        return t(name as TranslationKey)
    }
    return name
}

export function CategoryPicker({
    value,
    onChange,
    disabled,
    className,
}: CategoryPickerProps) {
    const { flatCategories, isLoading } = useCategories()

    const options = useMemo(
        () =>
            flatCategories.map((c) => ({
                value: c._id,
                label: `${c.icon} ${resolveCategoryName(c.name, c.isSystem)}`,
            })),
        [flatCategories],
    )

    if (isLoading) return <Skeleton className="h-8 w-full" />

    return (
        <Combobox
            value={value ? [value] : []}
            onChange={(values) => onChange(values[0])}
            options={options}
            placeholder="Select category..."
            emptyMessage="No categories"
            disabled={disabled}
            className={className}
        />
    )
}
