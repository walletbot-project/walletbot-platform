import { Button } from 'actify'
import { StateMessage } from '@/components/m3/state-message'
import { Skeleton } from '@/components/ui/skeleton'
import { useT } from '@/lib/i18n'

/** Placeholder while a detail route's backing query is still loading. */
export function DetailSkeleton() {
    return (
        <div className="flex flex-col gap-3 p-4">
            <Skeleton className="h-28 w-full rounded-2xl" />
            <Skeleton className="h-24 w-full rounded-2xl" />
        </div>
    )
}

/** The entity behind a detail route is gone (or the id is bogus). */
export function DetailNotFound({ onBack }: { onBack: () => void }) {
    const t = useT()
    return (
        <StateMessage
            icon="search_off"
            tone="error"
            title={t.common.notFoundTitle}
            detail={t.common.notFoundDescription}
            action={
                <Button variant="filled" onPress={onBack}>
                    {t.common.backToList}
                </Button>
            }
        />
    )
}
