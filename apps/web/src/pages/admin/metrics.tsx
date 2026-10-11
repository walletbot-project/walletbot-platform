import { Icon } from '@/components/m3/icon'
import { buttonVariants } from '@/components/ui/button'
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from '@/components/ui/card'
import { useT } from '@/lib/i18n'

/**
 * The production "accounts created by auth method" dashboard, the one linked
 * from the README. Metrics are not re-implemented here: Grafana already owns
 * them, so this section only points at it.
 */
const ACCOUNTS_DASHBOARD_URL =
    'https://fearlesspillar2602.grafana.net/d/geb465q/user-accounts-created-by-auth-method?var-Scope=production'

export function Metrics() {
    const t = useT()

    return (
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
            <p className="text-sm text-muted-foreground">
                {t.admin.metrics.subtitle}
            </p>
            <Card className="shrink-0">
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <Icon name="monitoring" size={18} />
                        {t.admin.metrics.dashboardsTitle}
                    </CardTitle>
                    <CardDescription>
                        {t.admin.metrics.dashboardsDescription}
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    <a
                        className={buttonVariants({ size: 'sm' })}
                        href={ACCOUNTS_DASHBOARD_URL}
                        target="_blank"
                        rel="noreferrer"
                    >
                        {t.admin.metrics.open}
                    </a>
                </CardContent>
            </Card>
        </div>
    )
}
