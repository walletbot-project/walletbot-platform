import { api } from '@wallet-bot/backend/api'
import { IconButton } from 'actify'
import { useMutation, usePaginatedQuery, useQuery } from 'convex/react'
import { type FormEvent, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
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

export function FeatureFlags() {
    const navigate = useNavigate()
    const isAdmin = useQuery(api.v1.featureFlags.queries.getMyAdminStatus)
    const flags = useQuery(
        api.v1.featureFlags.queries.listFlags,
        isAdmin === true ? {} : 'skip',
    )

    if (isAdmin === undefined) {
        return (
            <div className="flex flex-1 flex-col gap-4 p-4">
                <Skeleton className="h-24 w-full" />
                <Skeleton className="h-24 w-full" />
            </div>
        )
    }

    if (!isAdmin) {
        return (
            <div className="flex flex-1 flex-col items-center justify-center gap-2 p-4 text-center">
                <h2 className="text-lg font-medium">Not authorized</h2>
                <p className="text-sm text-muted-foreground">
                    You need admin access to view feature flags.
                </p>
            </div>
        )
    }

    return (
        <>
            <AppBar
                title="Feature flags"
                leading={
                    <IconButton
                        aria-label="Go back"
                        onPress={() => navigate(-1)}
                        className="text-on-surface-variant"
                    >
                        <Icon name="arrow_back" />
                    </IconButton>
                }
            />
            <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
                {flags === undefined ? (
                    <>
                        <Skeleton className="h-24 w-full" />
                        <Skeleton className="h-24 w-full" />
                    </>
                ) : (
                    flags.map((flag) => <FlagCard key={flag.key} flag={flag} />)
                )}
            </div>
        </>
    )
}

type FlagRow = {
    key: string
    description: string
    enabledByDefault: boolean
}

const OVERRIDES_PAGE_SIZE = 20

function FlagCard({ flag }: { flag: FlagRow }) {
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
            loading: 'Saving…',
            success: 'Default updated',
            error: 'Could not update default',
        })
    }

    const handleOverrideChange = (targetUserId: string, enabled: boolean) => {
        toast.promise(
            setUserOverride({ flagKey: flag.key, targetUserId, enabled }),
            {
                loading: 'Saving…',
                success: 'Override updated',
                error: 'Could not update override',
            },
        )
    }

    const handleRemoveOverride = (targetUserId: string) => {
        toast.promise(removeUserOverride({ flagKey: flag.key, targetUserId }), {
            loading: 'Removing…',
            success: 'Override removed',
            error: 'Could not remove override',
        })
    }

    const handleAddOverride = (e: FormEvent) => {
        e.preventDefault()
        const targetUserId = newUserId.trim()
        if (!targetUserId) return
        toast.promise(
            setUserOverride({ flagKey: flag.key, targetUserId, enabled: true }),
            {
                loading: 'Saving…',
                success: 'Override added',
                error: 'Could not add override',
            },
        )
        setNewUserId('')
    }

    return (
        <Card>
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
                <p className="text-sm font-medium">Per-user overrides</p>

                {overridesStatus === 'LoadingFirstPage' ? (
                    <Skeleton className="h-8 w-full" />
                ) : overrides.length === 0 ? (
                    <p className="text-sm text-muted-foreground">
                        No overrides yet.
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
                                        Remove
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
                        Load more
                    </Button>
                )}

                <form
                    className="flex items-center gap-2"
                    onSubmit={handleAddOverride}
                >
                    <Input
                        placeholder="User id"
                        value={newUserId}
                        onChange={(e) => setNewUserId(e.target.value)}
                    />
                    <Button type="submit" size="sm">
                        Add override
                    </Button>
                </form>
            </CardContent>
        </Card>
    )
}
