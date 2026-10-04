import type { MutationCtx } from '../_generated/server'
import { findAppUser, isLocalAppUserId } from '../appUsers/helpers'
import type { MetricInput } from './types'

export type UsageActor = {
    actorType: 'user' | 'local'
    actorKey: string
    userId?: string
    appUserId?: string
    parentId?: string
}

export const validInstallationId = (value: string): boolean =>
    /^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$/.test(value)

export const usageActor = async (
    ctx: MutationCtx,
    metric: Pick<MetricInput, 'userId' | 'appUserId'>,
): Promise<UsageActor | undefined> => {
    if (metric.userId) {
        return {
            actorType: 'user',
            actorKey: `user:${metric.userId}`,
            userId: metric.userId,
        }
    }
    if (!isLocalAppUserId(metric.appUserId)) return undefined
    const row = await findAppUser(ctx, metric.appUserId)
    if (row?.type !== 'local' || !row.parentId) return undefined
    return {
        actorType: 'local',
        actorKey: row.appUserId,
        appUserId: row.appUserId,
        parentId: row.parentId,
    }
}
