import { api } from '@wallet-bot/backend/api'
import { usePaginatedQuery } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { Icon } from '@/components/m3/icon'
import { Button } from '@/components/ui/button'
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { formatMoment } from '@/lib/format-moment'
import { useFormatLocale, useT } from '@/lib/i18n'

const PAGE_SIZE = 20

/** In-app feedback, newest first. Read-only: there is no triage state to set. */
export function Feedback() {
    const t = useT()
    const {
        results: items,
        status,
        loadMore,
    } = usePaginatedQuery(
        api.v1.admin.queries.listFeedback,
        {},
        { initialNumItems: PAGE_SIZE },
    )

    return (
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
            <p className="text-sm text-muted-foreground">
                {t.admin.feedback.subtitle}
            </p>

            {status === 'LoadingFirstPage' ? (
                <>
                    <Skeleton className="h-32 w-full shrink-0" />
                    <Skeleton className="h-32 w-full shrink-0" />
                </>
            ) : items.length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">
                    {t.admin.feedback.empty}
                </p>
            ) : (
                items.map((item) => <FeedbackCard key={item.id} item={item} />)
            )}

            {status === 'CanLoadMore' && (
                <Button variant="outline" onClick={() => loadMore(PAGE_SIZE)}>
                    {t.admin.loadMore}
                </Button>
            )}
        </div>
    )
}

type FeedbackRow = FunctionReturnType<
    typeof api.v1.admin.queries.listFeedback
>['page'][number]

function FeedbackCard({ item }: { item: FeedbackRow }) {
    const t = useT()
    const formatLocale = useFormatLocale()

    return (
        // shrink-0: see the note in feature-flags.tsx.
        <Card className="shrink-0">
            <CardHeader>
                <CardTitle className="truncate text-sm">
                    {item.email ??
                        (item.reporter === 'account'
                            ? t.admin.account
                            : t.admin.feedback.anonymous)}
                </CardTitle>
                <CardDescription>
                    {formatMoment(item.createdAt, formatLocale)} ·{' '}
                    {item.platform}
                    {item.appVersion ? ` ${item.appVersion}` : ''}
                    {item.locale ? ` · ${item.locale}` : ''}
                </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-3">
                <p className="whitespace-pre-wrap text-sm">{item.message}</p>
                {item.attachments.length > 0 && (
                    <div className="flex flex-col gap-1">
                        <span className="text-xs font-medium text-muted-foreground">
                            {t.admin.feedback.attachments}
                        </span>
                        <ul className="flex flex-col gap-1">
                            {item.attachments.map((attachment) => (
                                <li key={attachment.id}>
                                    {attachment.url ? (
                                        <a
                                            href={attachment.url}
                                            target="_blank"
                                            rel="noreferrer"
                                            className="inline-flex items-center gap-1 text-sm underline"
                                        >
                                            <Icon
                                                name="attach_file"
                                                size={16}
                                            />
                                            {attachment.name}
                                        </a>
                                    ) : (
                                        <span className="text-sm text-muted-foreground">
                                            {attachment.name}
                                        </span>
                                    )}
                                </li>
                            ))}
                        </ul>
                    </div>
                )}
            </CardContent>
        </Card>
    )
}
