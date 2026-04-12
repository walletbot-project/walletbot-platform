import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useMutation, useQuery } from 'convex/react'
import { useState } from 'react'
import { toast } from 'sonner'
import { CurrencySelector } from '@/components/shared/currency-selector'
import { Label } from '@/components/ui/label'

export function SettingsForm() {
    const settings = useQuery(api.settings.queries.getUserSettings)
    const updateSettings = useMutation(
        api.settings.mutations.updateUserSettings,
    )
    const [saving, setSaving] = useState(false)

    if (settings === undefined) {
        return (
            <div className="py-8 text-center text-sm text-muted-foreground">
                {t('common.loading')}
            </div>
        )
    }

    const handleCurrencyChange = async (currency: string) => {
        setSaving(true)
        try {
            await updateSettings({
                defaultCurrency: currency as 'USD' | 'ARS' | 'EUR' | 'BRL',
            })
            toast.success(t('toast.success.saved'))
        } catch (err) {
            toast.error(
                err instanceof Error ? err.message : t('toast.error.generic'),
            )
        } finally {
            setSaving(false)
        }
    }

    return (
        <div className="flex flex-col gap-6 rounded-xl border p-6">
            <div className="flex flex-col gap-1.5">
                <Label>{t('settings.defaultCurrency')}</Label>
                <CurrencySelector
                    value={settings.defaultCurrency}
                    onChange={handleCurrencyChange}
                    disabled={saving}
                />
                <p className="text-xs text-muted-foreground">
                    Used as the default currency when creating new accounts and
                    transactions.
                </p>
            </div>
        </div>
    )
}
