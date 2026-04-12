import { useMemo } from 'react'
import { Combobox } from '@/components/ui/combobox'
import { Skeleton } from '@/components/ui/skeleton'
import { useAccounts } from '@/hooks/use-accounts'

interface AccountSelectorProps {
    value: string | undefined
    onChange: (accountId: string | undefined) => void
    label?: string
    disabled?: boolean
    className?: string
}

export function AccountSelector({
    value,
    onChange,
    disabled,
    className,
}: AccountSelectorProps) {
    const { accounts, isLoading } = useAccounts()

    const options = useMemo(
        () =>
            accounts.map((a) => ({
                value: a._id,
                label: `${a.icon} ${a.name} (${a.currency})`,
            })),
        [accounts],
    )

    if (isLoading) return <Skeleton className="h-8 w-full" />

    return (
        <Combobox
            value={value ? [value] : []}
            onChange={(values) => onChange(values[0])}
            options={options}
            placeholder="Select account..."
            emptyMessage="No accounts"
            disabled={disabled}
            className={className}
        />
    )
}
