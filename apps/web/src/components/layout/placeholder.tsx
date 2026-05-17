import type { LucideIcon } from 'lucide-react'

export function Placeholder({
    icon: Icon,
    title,
    description,
}: {
    icon: LucideIcon
    title: string
    description?: string
}) {
    return (
        <div className="flex flex-1 items-center justify-center p-8">
            <div className="flex max-w-sm flex-col items-center gap-3 text-center">
                <div className="flex size-12 items-center justify-center rounded-full bg-muted">
                    <Icon className="size-5 text-muted-foreground" />
                </div>
                <h2 className="text-lg font-semibold">{title}</h2>
                {description ? (
                    <p className="text-sm text-muted-foreground">
                        {description}
                    </p>
                ) : null}
            </div>
        </div>
    )
}
