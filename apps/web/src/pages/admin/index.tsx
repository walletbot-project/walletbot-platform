import { IconButton } from 'actify'
import { useNavigate } from 'react-router-dom'
import { AppBar } from '@/components/m3/app-bar'
import { GroupedCard } from '@/components/m3/grouped-card'
import { Icon } from '@/components/m3/icon'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { type Messages, useT } from '@/lib/i18n'

const SECTIONS = [
    {
        to: '/admin/usability',
        icon: 'science',
        title: (t: Messages) => t.admin.usabilityTitle,
        description: (t: Messages) => t.admin.usabilityDescription,
    },
    {
        to: '/admin/agent-reports',
        icon: 'report',
        title: (t: Messages) => t.adminReports.title,
        description: (t: Messages) => t.admin.reportsDescription,
    },
    {
        to: '/admin/feature-flags',
        icon: 'flag',
        title: (t: Messages) => t.admin.flagsTitle,
        description: (t: Messages) => t.admin.flagsDescription,
    },
] as const

export function AdminHome() {
    const t = useT()
    const navigate = useNavigate()

    return (
        <>
            <AppBar
                title={t.admin.title}
                leading={
                    <IconButton
                        aria-label={t.common.goBack}
                        onPress={() => navigate('/')}
                        className="text-on-surface-variant"
                    >
                        <Icon name="arrow_back" />
                    </IconButton>
                }
            />
            <div className="min-h-0 flex-1 overflow-y-auto">
                <div
                    className="mx-auto flex w-full max-w-2xl flex-col p-4"
                    style={{ gap: GROUP_SPACING }}
                >
                    {SECTIONS.map((section, index) => (
                        <GroupedCard
                            key={section.to}
                            radius={groupedRadius(index, SECTIONS.length)}
                            onClick={() => navigate(section.to)}
                        >
                            <div className="flex items-center gap-4 px-4 py-4">
                                <Icon
                                    name={section.icon}
                                    filled
                                    className="text-on-surface-variant"
                                />
                                <div className="flex min-w-0 flex-1 flex-col">
                                    <span className="m3-body-large">
                                        {section.title(t)}
                                    </span>
                                    <span className="m3-body-medium text-on-surface-variant">
                                        {section.description(t)}
                                    </span>
                                </div>
                                <Icon
                                    name="chevron_right"
                                    className="text-on-surface-variant"
                                />
                            </div>
                        </GroupedCard>
                    ))}
                </div>
            </div>
        </>
    )
}
