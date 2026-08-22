import {
    isRouteErrorResponse,
    useNavigate,
    useRouteError,
} from 'react-router-dom'
import { Icon } from '@/components/m3/icon'
import { Button } from '@/components/ui/button'
import {
    Collapsible,
    CollapsibleContent,
    CollapsibleTrigger,
} from '@/components/ui/collapsible'
import { useT } from '@/lib/i18n'

function getErrorDetails(error: unknown): string {
    if (isRouteErrorResponse(error)) {
        return `${String(error.status)} ${error.statusText}${error.data ? `\n${String(error.data)}` : ''}`
    }
    if (error instanceof Error) {
        return error.stack ?? error.message
    }
    return String(error)
}

export function GlobalErrorBoundary() {
    const error = useRouteError()
    const navigate = useNavigate()
    const t = useT()

    if (isRouteErrorResponse(error) && error.status === 404) {
        return (
            <div className="flex min-h-screen flex-col items-center justify-center gap-6 text-center">
                <div className="text-muted-foreground/20 text-[8rem] leading-none font-bold select-none">
                    404
                </div>
                <div className="flex flex-col gap-2">
                    <h2 className="text-2xl font-semibold tracking-tight">
                        {t.errors.pageNotFound}
                    </h2>
                    <p className="text-muted-foreground text-sm max-w-sm mx-auto">
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

    const details = getErrorDetails(error)

    return (
        <div className="flex min-h-screen flex-col items-center justify-center gap-6 text-center px-4">
            <div className="bg-destructive/10 rounded-full p-4">
                <Icon name="error" filled size={40} className="text-error" />
            </div>
            <div className="flex flex-col gap-2">
                <h2 className="text-2xl font-semibold tracking-tight">
                    {t.errors.somethingWentWrong}
                </h2>
                <p className="text-muted-foreground text-sm max-w-md mx-auto">
                    {t.errors.unexpectedError}
                </p>
            </div>
            <div className="flex items-center gap-3 pt-2">
                <Button
                    variant="outline"
                    onClick={() => window.location.reload()}
                >
                    {t.errors.refreshPage}
                </Button>
                <Button onClick={() => navigate('/')}>
                    <Icon name="home" filled />
                    {t.common.home}
                </Button>
            </div>
            <ErrorDetails details={details} />
        </div>
    )
}

function ErrorDetails({ details }: { details: string }) {
    const t = useT()
    return (
        <Collapsible className="w-full max-w-lg mt-2">
            <CollapsibleTrigger className="text-muted-foreground hover:text-foreground flex items-center gap-1 mx-auto text-xs cursor-pointer transition-colors">
                <Icon
                    name="expand_more"
                    filled
                    size={14}
                    className="transition-transform in-data-panel-open:rotate-180"
                />
                {t.errors.viewErrorDetails}
            </CollapsibleTrigger>
            <CollapsibleContent className="mt-3">
                <pre className="bg-muted text-muted-foreground rounded-md p-4 text-left text-xs overflow-auto max-h-48 whitespace-pre-wrap wrap-break-word">
                    {details}
                </pre>
            </CollapsibleContent>
        </Collapsible>
    )
}
