// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import { convexTest } from 'convex-test'
import { expect, it } from 'vitest'
import { internal } from './_generated/api'
import schema from './schema'

const modules = import.meta.glob('./**/*.ts')
const localAccountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const appUserId = `local:${localAccountId}`

const claim = (
    t: ReturnType<typeof convexTest>,
    userId: string,
    createdNow: boolean,
    id = localAccountId,
) =>
    t.mutation(internal.appUsers.internal.claimLocal, {
        localAccountId: id,
        userId,
        createdNow,
    })

it('links an existing local identity to the account created by the promotion', async () => {
    const t = convexTest(schema, modules)
    await t.mutation(internal.appUsers.internal.registerLocal, {
        deviceId: 'device-origin',
        localAccountId,
    })
    expect(await claim(t, 'user-1', true)).toEqual({ ok: true })
    await t.run(async (ctx) => {
        const rows = await ctx.db.query('appUsers').take(10)
        expect(rows).toHaveLength(1)
        expect(rows[0]).toMatchObject({
            appUserId,
            type: 'registered',
            userId: 'user-1',
            // Origin is kept so the creator group is not lost on promotion.
            parentId: expect.stringMatching(/^device:/),
        })
    })
})

it('creates an already-linked row for a local account that never used the agent', async () => {
    const t = convexTest(schema, modules)
    expect(await claim(t, 'user-1', true)).toEqual({ ok: true })
    await t.run(async (ctx) => {
        const rows = await ctx.db.query('appUsers').take(10)
        expect(rows).toHaveLength(1)
        expect(rows[0]).toMatchObject({
            appUserId,
            type: 'registered',
            userId: 'user-1',
        })
    })
})

it('refuses to merge into a user that already existed', async () => {
    const t = convexTest(schema, modules)
    await t.mutation(internal.appUsers.internal.registerLocal, {
        deviceId: 'device-origin',
        localAccountId,
    })
    expect(await claim(t, 'existing-user', false)).toEqual({
        ok: false,
        error: 'account_exists',
    })
    await t.run(async (ctx) => {
        const rows = await ctx.db.query('appUsers').take(10)
        expect(rows).toHaveLength(1)
        expect(rows[0]).toMatchObject({ appUserId, type: 'local' })
        expect(rows[0].userId).toBeUndefined()
    })
})

it('lets the user the identity is already linked to repeat the claim, and nobody else', async () => {
    const t = convexTest(schema, modules)
    expect(await claim(t, 'user-1', true)).toEqual({ ok: true })
    // The sign-in after email verification: the account is no longer new.
    expect(await claim(t, 'user-1', false)).toEqual({ ok: true })
    expect(await claim(t, 'user-2', true)).toEqual({
        ok: false,
        error: 'local_account_claimed',
    })
    await t.run(async (ctx) => {
        const rows = await ctx.db.query('appUsers').take(10)
        expect(rows).toHaveLength(1)
        expect(rows[0].userId).toBe('user-1')
    })
})

it('rejects an id that is not a local account UUID', async () => {
    const t = convexTest(schema, modules)
    expect(await claim(t, 'user-1', true, 'not-a-uuid')).toEqual({
        ok: false,
        error: 'invalid_local_identity',
    })
    await t.run(async (ctx) => {
        expect(await ctx.db.query('appUsers').take(10)).toHaveLength(0)
    })
})

const carryover = (t: ReturnType<typeof convexTest>, userId: string) =>
    t.mutation(internal.appUsers.internal.applyCarryover, {
        userId,
        acceptance: {
            documents: ['terms', 'privacy'],
            ageConfirmed: true,
            platform: 'ios',
        },
        aiConsent: { platform: 'ios', appVersion: '0.4.0' },
        defaultCurrency: 'USD',
    })

it('carries the consent, terms and currency decided on the device over to the user', async () => {
    const t = convexTest(schema, modules)
    await carryover(t, 'user-1')
    await t.run(async (ctx) => {
        const rows = await ctx.db.query('legalAcceptances').take(10)
        expect(rows.map((row) => row.document).sort()).toEqual([
            'ai',
            'privacy',
            'terms',
        ])
        const settings = await ctx.db.query('userSettings').take(10)
        expect(settings).toHaveLength(1)
        expect(settings[0]).toMatchObject({
            userId: 'user-1',
            defaultCurrency: 'USD',
        })
    })
})

it('carries over once: a repeat neither duplicates rows nor undoes a later change', async () => {
    const t = convexTest(schema, modules)
    await carryover(t, 'user-1')
    await t.run(async (ctx) => {
        const settings = await ctx.db.query('userSettings').unique()
        if (!settings) throw new Error('settings missing')
        await ctx.db.patch(settings._id, { defaultCurrency: 'EUR' })
    })
    await carryover(t, 'user-1')
    await t.run(async (ctx) => {
        expect(await ctx.db.query('legalAcceptances').take(10)).toHaveLength(3)
        const settings = await ctx.db.query('userSettings').unique()
        expect(settings?.defaultCurrency).toBe('EUR')
    })
})

it('ignores a currency that is not a currency code', async () => {
    const t = convexTest(schema, modules)
    await t.mutation(internal.appUsers.internal.applyCarryover, {
        userId: 'user-1',
        defaultCurrency: 'not-a-currency',
    })
    await t.run(async (ctx) => {
        expect(await ctx.db.query('userSettings').take(10)).toHaveLength(0)
    })
})
