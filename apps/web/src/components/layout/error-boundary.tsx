import { ArrowLeft, ChevronDown, Home, OctagonAlert } from 'lucide-react'
import {
    isRouteErrorResponse,
    useNavigate,
    useRouteError,
} from 'react-router-dom'
import { Button } from '@/components/ui/button'
import {
    Collapsible,
    CollapsibleContent,
    CollapsibleTrigger,
} from '@/components/ui/collapsible'

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

    if (isRouteErrorResponse(error) && error.status === 404) {
        return (
            <div className="flex min-h-screen flex-col items-center justify-center gap-6 text-center">
                <div className="text-muted-foreground/20 text-[8rem] leading-none font-bold select-none">
                    404
                </div>
                <div className="flex flex-col gap-2">
                    <h2 className="text-2xl font-semibold tracking-tight">
                        Page not found
                    </h2>
                    <p className="text-muted-foreground text-sm max-w-sm mx-auto">
                        The page you're looking for doesn't exist or has been
                        moved.
                    </p>
                </div>
                <div className="flex items-center gap-3 pt-2">
                    <Button variant="outline" onClick={() => navigate(-1)}>
                        <ArrowLeft />
                        Go back
                    </Button>
                    <Button onClick={() => navigate('/')}>
                        <Home />
                        Home
                    </Button>
                </div>
            </div>
        )
    }

    const details = getErrorDetails(error)

    return (
        <div className="flex min-h-screen flex-col items-center justify-center gap-6 text-center px-4">
            <div className="bg-destructive/10 rounded-full p-4">
                <OctagonAlert className="text-destructive size-10" />
            </div>
            <div className="flex flex-col gap-2">
                <h2 className="text-2xl font-semibold tracking-tight">
                    Something went wrong
                </h2>
                <p className="text-muted-foreground text-sm max-w-md mx-auto">
                    An unexpected error occurred. Try refreshing the page or
                    heading back.
                </p>
            </div>
            <div className="flex items-center gap-3 pt-2">
                <Button
                    variant="outline"
                    onClick={() => window.location.reload()}
                >
                    Refresh page
                </Button>
                <Button onClick={() => navigate('/')}>
                    <Home />
                    Home
                </Button>
            </div>
            <ErrorDetails details={details} />
        </div>
    )
}

function ErrorDetails({ details }: { details: string }) {
    return (
        <Collapsible className="w-full max-w-lg mt-2">
            <CollapsibleTrigger className="text-muted-foreground hover:text-foreground flex items-center gap-1 mx-auto text-xs cursor-pointer transition-colors">
                <ChevronDown className="size-3.5 transition-transform in-data-panel-open:rotate-180" />
                View error details
            </CollapsibleTrigger>
            <CollapsibleContent className="mt-3">
                <pre className="bg-muted text-muted-foreground rounded-md p-4 text-left text-xs overflow-auto max-h-48 whitespace-pre-wrap wrap-break-word">
                    {details}
                </pre>
            </CollapsibleContent>
        </Collapsible>
    )
}
