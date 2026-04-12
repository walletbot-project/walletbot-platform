import { t } from '@wallet-bot/shared'
import { DangerZone } from '@/components/settings/danger-zone'
import { SettingsForm } from '@/components/settings/settings-form'
import { PageHeader } from '@/components/shared/page-header'

export function Settings() {
    return (
        <>
            <PageHeader title={t('settings.title')} />
            <div className="flex flex-col gap-6">
                <SettingsForm />
                <DangerZone />
            </div>
        </>
    )
}
