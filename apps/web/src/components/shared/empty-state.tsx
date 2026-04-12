import type { LucideIcon } from 'lucide-react'
import { Button } from '@/components/ui/button'

interface EmptyStateProps {
    icon: LucideIcon
    title: string
    description?: string
    action?: {
        label: string
        onClick: () => void
    }
}

export function EmptyState({
    icon: Icon,
    title,
    description,
    action,
}: EmptyStateProps) {
    return (
        <div className="flex flex-col items-center justify-center gap-3 py-12 text-center">
            <div className="rounded-full bg-muted p-3">
                <Icon className="size-6 text-muted-foreground" />
            </div>
            <div className="space-y-1">
                <p className="text-sm font-medium">{title}</p>
                {description && (
                    <p className="text-sm text-muted-foreground">
                        {description}
                    </p>
                )}
            </div>
            {action && (
                <Button size="sm" onClick={action.onClick}>
                    {action.label}
                </Button>
            )}
        </div>
    )
}
