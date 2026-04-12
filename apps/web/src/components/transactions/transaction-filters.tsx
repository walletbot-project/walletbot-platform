import { t } from '@wallet-bot/shared'
import { X } from 'lucide-react'
import { useSearchParams } from 'react-router-dom'
import { AccountSelector } from '@/components/shared/account-selector'
import { CategoryPicker } from '@/components/shared/category-picker'
import { DatePickerField } from '@/components/shared/date-picker-field'
import { Button } from '@/components/ui/button'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'

export function TransactionFilters() {
    const [searchParams, setSearchParams] = useSearchParams()

    const type = searchParams.get('type') ?? 'all'
    const fromDate = searchParams.get('from') ?? undefined
    const toDate = searchParams.get('to') ?? undefined
    const category = searchParams.get('category') ?? undefined
    const account = searchParams.get('account') ?? undefined

    const hasFilters =
        type !== 'all' || fromDate || toDate || category || account

    const setParam = (key: string, value: string | undefined) => {
        setSearchParams((prev) => {
            const next = new URLSearchParams(prev)
            if (value) {
                next.set(key, value)
            } else {
                next.delete(key)
            }
            return next
        })
    }

    const clearFilters = () => {
        setSearchParams({})
    }

    return (
        <div className="flex flex-col gap-3">
            <Tabs
                value={type}
                onValueChange={(v) =>
                    setParam('type', v === 'all' ? undefined : v)
                }
            >
                <TabsList>
                    <TabsTrigger value="all">{t('common.all')}</TabsTrigger>
                    <TabsTrigger value="expense">
                        {t('transactions.type.expense')}
                    </TabsTrigger>
                    <TabsTrigger value="income">
                        {t('transactions.type.income')}
                    </TabsTrigger>
                    <TabsTrigger value="transfer">
                        {t('transactions.type.transfer')}
                    </TabsTrigger>
                </TabsList>
            </Tabs>

            <div className="flex flex-wrap items-center gap-2">
                <DatePickerField
                    value={fromDate}
                    onChange={(v) => setParam('from', v)}
                    placeholder="From date"
                />
                <DatePickerField
                    value={toDate}
                    onChange={(v) => setParam('to', v)}
                    placeholder="To date"
                />
                <CategoryPicker
                    value={category}
                    onChange={(v) => setParam('category', v)}
                    className="w-44"
                />
                <AccountSelector
                    value={account}
                    onChange={(v) => setParam('account', v)}
                    className="w-44"
                />
                {hasFilters && (
                    <Button variant="ghost" size="sm" onClick={clearFilters}>
                        <X className="size-3.5" />
                        Clear
                    </Button>
                )}
            </div>
        </div>
    )
}
