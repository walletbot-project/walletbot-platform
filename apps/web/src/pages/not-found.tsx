import { useNavigate } from 'react-router-dom'
import { Icon } from '@/components/m3/icon'
import { Button } from '@/components/ui/button'
import { useT } from '@/lib/i18n'

export function NotFound() {
    const navigate = useNavigate()
    const t = useT()

    return (
        <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8 text-center">
            <div className="m3-display-large text-on-surface-variant/20 select-none">
                404
            </div>
            <div className="flex flex-col gap-2">
                <h2 className="m3-headline-small font-semibold">
                    {t.errors.pageNotFound}
                </h2>
                <p className="m3-body-medium mx-auto max-w-sm text-on-surface-variant">
                    {t.errors.pageNotFoundDescription}
                </p>
            </div>
            <div className="flex items-center gap-3 pt-2">
                <Button variant="outline" onClick={() => navigate(-1)}>
                    <Icon name="arrow_back" />
                    {t.common.goBack}
                </Button>
                <Button onClick={() => navigate('/')}>
                    <Icon name="home" filled />
                    {t.common.home}
                </Button>
            </div>
        </div>
    )
}
