import { isValidCurrencyCode, MAX_DEVICE_ID_LENGTH } from '@wallet-bot/shared'
import type { MutationCtx, QueryCtx } from '../_generated/server'
import {
    type RecordAcceptancesArgs,
    type RecordAiConsentArgs,
    recordAcceptances,
    recordAiConsent,
    resolveAcceptanceStatus,
    resolveAiConsent,
} from '../legal/helpers'

export const isLocalAppUserId = (value: unknown): value is string =>
    typeof value === 'string' &&
    /^local:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
        value,
    )

export const findAppUser = (ctx: MutationCtx | QueryCtx, appUserId: string) =>
    ctx.db
        .query('appUsers')
        .withIndex('by_appUserId', (q) => q.eq('appUserId', appUserId))
        .unique()

export const registerLocalAppUser = async (
    ctx: MutationCtx,
    deviceId: string,
    localAccountId: string,
): Promise<
    | { ok: true; appUserId: string; parentId: string }
    | { ok: false; error: string }
> => {
    const device = deviceId.trim()
    const appUserId = `local:${localAccountId.trim().toLowerCase()}`
    if (
        !device ||
        device === 'unknown' ||
        device.length > MAX_DEVICE_ID_LENGTH ||
        !isLocalAppUserId(appUserId)
    ) {
        return { ok: false, error: 'invalid_local_identity' }
    }
    const existing = await findAppUser(ctx, appUserId)
    if (existing) {
        // Origin is immutable: restoring an account on another installation
        // must not silently move it to a different creator group.
        if (existing.type !== 'local' || !existing.parentId)
            return { ok: false, error: 'not_local' }
        if (Date.now() - existing.lastSeenAt >= 60 * 60 * 1000) {
            await ctx.db.patch(existing._id, { lastSeenAt: Date.now() })
        }
        return { ok: true, appUserId, parentId: existing.parentId }
    }
    const digest = await crypto.subtle.digest(
        'SHA-256',
        new TextEncoder().encode(`device:${device}`),
    )
    const hash = Array.from(new Uint8Array(digest))
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('')
    const parentId = `device:${hash}`
    await ctx.db.insert('appUsers', {
        appUserId,
        type: 'local',
        parentId,
        createdAt: Date.now(),
        lastSeenAt: Date.now(),
    })
    return { ok: true, appUserId, parentId }
}

export type ClaimLocalResult =
    | { ok: true }
    | {
          ok: false
          error:
              | 'invalid_local_identity'
              | 'account_exists'
              | 'local_account_claimed'
      }

// Links a device-created local identity to the registered user it was
// promoted into. Only the link: usage already recorded under `local:<uuid>`
// stays under that key, because `agentUsageMonthly` groups by `actorKey` and
// nothing reads this link to join the two (WAL-222).
//
// `createdNow` is established by the caller from the sign-in/sign-up itself,
// never from the client: only an account created by this very promotion may
// claim a local identity. A user that already existed must not be able to
// absorb one (promotion never merges into an existing online account), unless
// it is the user the identity was already linked to — which is what makes a
// retry after a half-finished attempt, or the sign-in that follows email
// verification, idempotent.
export const claimLocalAppUser = async (
    ctx: MutationCtx,
    localAccountId: string,
    userId: string,
    createdNow: boolean,
): Promise<ClaimLocalResult> => {
    const appUserId = `local:${localAccountId.trim().toLowerCase()}`
    if (!isLocalAppUserId(appUserId)) {
        return { ok: false, error: 'invalid_local_identity' }
    }
    const existing = await findAppUser(ctx, appUserId)
    if (existing?.type === 'registered') {
        return existing.userId === userId
            ? { ok: true }
            : { ok: false, error: 'local_account_claimed' }
    }
    if (!createdNow) return { ok: false, error: 'account_exists' }
    const now = Date.now()
    if (existing) {
        await ctx.db.patch(existing._id, {
            type: 'registered',
            userId,
            lastSeenAt: now,
        })
    } else {
        // A local account that never used the agent has no row yet; create it
        // already linked so a later retry finds the claim.
        await ctx.db.insert('appUsers', {
            appUserId,
            type: 'registered',
            userId,
            createdAt: now,
            lastSeenAt: now,
        })
    }
    return { ok: true }
}

/**
 * What a local account already settled on the device, handed to the server
 * with the promotion request because the promoted session does not exist yet
 * when it is sent. Every piece is optional and re-validated here: the client
 * is not trusted, and each piece is something the user can only do to their
 * own, brand-new account.
 */
export type PromotionCarryover = {
    acceptance?: Omit<RecordAcceptancesArgs, 'userId'>
    aiConsent?: Omit<RecordAiConsentArgs, 'userId'>
    defaultCurrency?: string
}

/**
 * Applies a local account's device-only state to the user it was promoted to,
 * so the account does not come out of the promotion asking for, or reverting,
 * what the user already decided.
 *
 * Safe to run again — a failed promotion is retried, and an email promotion
 * signs in a second time after verification: each piece is skipped when the
 * user already has it, and never overwrites a value they have since changed.
 */
export const applyPromotionCarryover = async (
    ctx: MutationCtx,
    userId: string,
    carryover: PromotionCarryover,
): Promise<void> => {
    const { acceptance, aiConsent, defaultCurrency } = carryover

    if (acceptance) {
        const status = await resolveAcceptanceStatus(ctx, userId)
        const documents = acceptance.documents.filter(
            (document) => status[document].status !== 'current',
        )
        if (documents.length > 0) {
            await recordAcceptances(ctx, { userId, ...acceptance, documents })
        }
    }

    if (aiConsent && !(await resolveAiConsent(ctx, userId)).accepted) {
        await recordAiConsent(ctx, { userId, ...aiConsent })
    }

    if (defaultCurrency !== undefined && isValidCurrencyCode(defaultCurrency)) {
        const existing = await ctx.db
            .query('userSettings')
            .withIndex('by_user', (q) => q.eq('userId', userId))
            .unique()
        if (!existing) {
            await ctx.db.insert('userSettings', {
                userId,
                defaultCurrency,
                updatedAt: BigInt(Date.now()),
            })
        }
    }
}
