import { api } from '@wallet-bot/backend/api'
import { useMutation, usePaginatedQuery, useQuery } from 'convex/react'
import { type FormEvent, useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { Switch } from '@/components/ui/switch'
import { useT } from '@/lib/i18n'

export function FeatureFlags() {
    const flags = useQuery(api.v1.featureFlags.queries.listFlags)

    return (
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
            {flags === undefined ? (
                <>
                    <Skeleton className="h-24 w-full shrink-0" />
                    <Skeleton className="h-24 w-full shrink-0" />
                </>
            ) : (
                flags.map((flag) => <FlagCard key={flag.key} flag={flag} />)
            )}
        </div>
    )
}

type FlagRow = {
    key: string
    description: string
    enabledByDefault: boolean
}

const OVERRIDES_PAGE_SIZE = 20

function FlagCard({ flag }: { flag: FlagRow }) {
    const t = useT()
    const {
        results: overrides,
        status: overridesStatus,
        loadMore: loadMoreOverrides,
    } = usePaginatedQuery(
        api.v1.featureFlags.queries.listOverrides,
        { flagKey: flag.key },
        { initialNumItems: OVERRIDES_PAGE_SIZE },
    )
    const setFlagDefault = useMutation(
        api.v1.featureFlags.mutations.setFlagDefault,
    )
    const setUserOverride = useMutation(
        api.v1.featureFlags.mutations.setUserOverride,
    )
    const removeUserOverride = useMutation(
        api.v1.featureFlags.mutations.removeUserOverride,
    )
    const [newUserId, setNewUserId] = useState('')

    const handleDefaultChange = (enabled: boolean) => {
        toast.promise(setFlagDefault({ key: flag.key, enabled }), {
            loading: t.common.saving,
            success: t.admin.flags.defaultUpdated,
            error: t.admin.flags.defaultFailed,
        })
    }

    const handleOverrideChange = (targetUserId: string, enabled: boolean) => {
        toast.promise(
            setUserOverride({ flagKey: flag.key, targetUserId, enabled }),
            {
                loading: t.common.saving,
                success: t.admin.flags.overrideUpdated,
                error: t.admin.flags.overrideFailed,
            },
        )
    }

    const handleRemoveOverride = (targetUserId: string) => {
        toast.promise(removeUserOverride({ flagKey: flag.key, targetUserId }), {
            loading: t.admin.flags.removing,
            success: t.admin.flags.overrideRemoved,
            error: t.admin.flags.overrideRemoveFailed,
        })
    }

    const handleAddOverride = (e: FormEvent) => {
        e.preventDefault()
        const targetUserId = newUserId.trim()
        if (!targetUserId) return
        toast.promise(
            setUserOverride({ flagKey: flag.key, targetUserId, enabled: true }),
            {
                loading: t.common.saving,
                success: t.admin.flags.overrideAdded,
                error: t.admin.flags.overrideAddFailed,
            },
        )
        setNewUserId('')
    }

    return (
        // shrink-0: a flex child defaults to shrinking, so without this the
        // cards compress to fit the viewport and clip their own contents
        // instead of overflowing the scroll container above.
        <Card className="shrink-0">
            <CardHeader>
                <CardTitle className="flex items-center justify-between gap-2">
                    <span>{flag.key}</span>
                    <Switch
                        checked={flag.enabledByDefault}
                        onCheckedChange={handleDefaultChange}
                    />
                </CardTitle>
                <CardDescription>{flag.description}</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-3">
                <p className="text-sm font-medium">{t.admin.flags.overrides}</p>

                {overridesStatus === 'LoadingFirstPage' ? (
                    <Skeleton className="h-8 w-full" />
                ) : overrides.length === 0 ? (
                    <p className="text-sm text-muted-foreground">
                        {t.admin.flags.noOverrides}
                    </p>
                ) : (
                    <ul className="divide-y rounded-md border">
                        {overrides.map((override) => (
                            <li
                                key={override.userId}
                                className="flex items-center justify-between gap-2 px-3 py-2"
                            >
                                <span className="truncate text-sm">
                                    {override.email}
                                </span>
                                <div className="flex items-center gap-2">
                                    <Switch
                                        checked={override.enabled}
                                        onCheckedChange={(enabled) =>
                                            handleOverrideChange(
                                                override.userId,
                                                enabled,
                                            )
                                        }
                                    />
                                    <Button
                                        size="sm"
                                        variant="ghost"
                                        onClick={() =>
                                            handleRemoveOverride(
                                                override.userId,
                                            )
                                        }
                                    >
                                        {t.admin.flags.remove}
                                    </Button>
                                </div>
                            </li>
                        ))}
                    </ul>
                )}

                {overridesStatus === 'CanLoadMore' && (
                    <Button
                        size="sm"
                        variant="outline"
                        onClick={() => loadMoreOverrides(OVERRIDES_PAGE_SIZE)}
                    >
                        {t.admin.loadMore}
                    </Button>
                )}

                <form
                    className="flex items-center gap-2"
                    onSubmit={handleAddOverride}
                >
                    <Input
                        placeholder={t.admin.flags.userId}
                        value={newUserId}
                        onChange={(e) => setNewUserId(e.target.value)}
                    />
                    <Button type="submit" size="sm">
                        {t.admin.flags.addOverride}
                    </Button>
                </form>
            </CardContent>
        </Card>
    )
}
