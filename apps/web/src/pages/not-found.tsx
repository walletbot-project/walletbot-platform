import { ArrowLeft, Home } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { useT } from '@/lib/i18n'

export function NotFound() {
    const navigate = useNavigate()
    const t = useT()

    return (
        <div className="flex min-h-screen flex-col items-center justify-center gap-6 text-center">
            <div className="text-muted-foreground/20 text-[8rem] leading-none font-bold select-none">
                404
            </div>
            <div className="flex flex-col gap-2">
                <h2 className="text-2xl font-semibold tracking-tight">
                    {t.errors.pageNotFound}
                </h2>
                <p className="text-muted-foreground mx-auto max-w-sm text-sm">
                    {t.errors.pageNotFoundDescription}
                </p>
            </div>
            <div className="flex items-center gap-3 pt-2">
                <Button variant="outline" onClick={() => navigate(-1)}>
                    <ArrowLeft />
                    {t.common.goBack}
                </Button>
                <Button onClick={() => navigate('/')}>
                    <Home />
                    {t.common.home}
                </Button>
            </div>
        </div>
    )
}
