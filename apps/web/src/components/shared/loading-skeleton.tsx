import { Skeleton } from '@/components/ui/skeleton'

interface ListSkeletonProps {
    count?: number
}

export function ListSkeleton({ count = 5 }: ListSkeletonProps) {
    return (
        <div className="flex flex-col gap-2">
            {Array.from({ length: count }, (_, i) => (
                <div
                    key={i}
                    className="flex items-center gap-3 rounded-lg border p-3"
                >
                    <Skeleton className="size-8 rounded-full" />
                    <div className="flex-1 space-y-1.5">
                        <Skeleton className="h-3.5 w-32" />
                        <Skeleton className="h-3 w-20" />
                    </div>
                    <Skeleton className="h-4 w-16" />
                </div>
            ))}
        </div>
    )
}

export function CardSkeleton() {
    return (
        <div className="rounded-xl border p-6">
            <div className="space-y-3">
                <Skeleton className="h-4 w-24" />
                <Skeleton className="h-8 w-32" />
            </div>
        </div>
    )
}
