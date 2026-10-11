import { api } from '@wallet-bot/backend/api'
import { usePaginatedQuery, useQuery } from 'convex/react'
import { type FormEvent, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { formatMoment } from '@/lib/format-moment'
import { useFormatLocale, useT } from '@/lib/i18n'

const PAGE_SIZE = 25

type UserRow = {
    id: string
    email: string
    name: string
    emailVerified: boolean
    createdAt: number
    isAdmin: boolean
}

/**
 * Accounts, newest first, plus an exact-email lookup. There is no partial
 * search on purpose: it would mean filtering every account in memory.
 */
export function Users() {
    const t = useT()
    const [draft, setDraft] = useState('')
    const [email, setEmail] = useState('')

    const {
        results: users,
        status,
        loadMore,
    } = usePaginatedQuery(
        api.v1.admin.queries.listUsers,
        {},
        { initialNumItems: PAGE_SIZE },
    )
    const found = useQuery(
        api.v1.admin.queries.findUserByEmail,
        email ? { email } : 'skip',
    )

    const submit = (e: FormEvent) => {
        e.preventDefault()
        setEmail(draft.trim())
    }

    const clear = () => {
        setDraft('')
        setEmail('')
    }

    return (
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
            <p className="text-sm text-muted-foreground">
                {t.admin.users.subtitle}
            </p>

            <form className="flex items-center gap-2" onSubmit={submit}>
                <Input
                    type="email"
                    placeholder={t.admin.users.searchPlaceholder}
                    value={draft}
                    onChange={(e) => setDraft(e.target.value)}
                />
                <Button type="submit" size="sm">
                    {t.admin.users.search}
                </Button>
                {email && (
                    <Button
                        type="button"
                        size="sm"
                        variant="ghost"
                        onClick={clear}
                    >
                        {t.admin.users.clearSearch}
                    </Button>
                )}
            </form>

            {email ? (
                found === undefined ? (
                    <Skeleton className="h-16 w-full shrink-0" />
                ) : found === null ? (
                    <p className="py-8 text-center text-sm text-muted-foreground">
                        {t.admin.users.notFound}
                    </p>
                ) : (
                    <ul className="divide-y rounded-md border">
                        <UserItem user={found} />
                    </ul>
                )
            ) : status === 'LoadingFirstPage' ? (
                <>
                    <Skeleton className="h-16 w-full shrink-0" />
                    <Skeleton className="h-16 w-full shrink-0" />
                </>
            ) : users.length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">
                    {t.admin.users.empty}
                </p>
            ) : (
                <ul className="divide-y rounded-md border">
                    {users.map((user) => (
                        <UserItem key={user.id} user={user} />
                    ))}
                </ul>
            )}

            {!email && status === 'CanLoadMore' && (
                <Button variant="outline" onClick={() => loadMore(PAGE_SIZE)}>
                    {t.admin.loadMore}
                </Button>
            )}
        </div>
    )
}

function UserItem({ user }: { user: UserRow }) {
    const t = useT()
    const formatLocale = useFormatLocale()

    return (
        <li className="flex flex-col gap-1 px-3 py-2">
            <div className="flex flex-wrap items-center gap-2">
                <span className="truncate text-sm font-medium">
                    {user.email}
                </span>
                {user.isAdmin && (
                    <span className="rounded-full bg-muted px-2 py-0.5 text-xs">
                        {t.admin.users.admin}
                    </span>
                )}
                <span className="rounded-full bg-muted px-2 py-0.5 text-xs">
                    {user.emailVerified
                        ? t.admin.users.verified
                        : t.admin.users.unverified}
                </span>
            </div>
            <p className="text-xs text-muted-foreground">
                {user.name || t.admin.users.unnamed} · {t.admin.users.joined}{' '}
                {formatMoment(user.createdAt, formatLocale)}
            </p>
            <p className="truncate font-mono text-xs text-muted-foreground">
                {t.admin.users.userId}: {user.id}
            </p>
        </li>
    )
}
