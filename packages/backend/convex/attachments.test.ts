// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import rateLimiter from '@convex-dev/rate-limiter/test'
import { ATTACHMENT_TTL_MS } from '@wallet-bot/shared'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api, internal } from './_generated/api'
import type { Id } from './_generated/dataModel'
import schema from './schema'

// convex-test records no content type for stored files, so registration can
// only be driven up to the type check here. Tests that need an attachment
// seed the row the way `register` writes it.

const modules = import.meta.glob('./**/*.ts')
const DEVICE = '3f2b8c1e-9a4d-4e6f-8b2a-1c3d5e7f9a0b'

beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(Date.UTC(2026, 8, 25, 12))
    vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
})

afterEach(() => {
    vi.unstubAllEnvs()
    vi.useRealTimers()
})

async function fixture({ enabled = true }: { enabled?: boolean } = {}) {
    const t = convexTest(schema, modules)
    rateLimiter.register(t)
    await t.run(async (ctx) => {
        await ctx.db.insert('featureFlags', {
            key: 'agentAttachments',
            description: '',
            enabledByDefault: enabled,
            updatedAt: 0n,
            updatedBy: 'test',
        })
    })
    const as = (userId: string) =>
        t.withIdentity({
            subject: userId,
            issuer: 'https://test.convex.site/native-auth',
        })
    const store = () =>
        t.run(
            async (ctx): Promise<Id<'_storage'>> =>
                ctx.storage.store(new Blob(['%PDF-'])),
        )
    const seed = (owner: { userId: string } | { deviceId: string }) =>
        t.run(async (ctx) => {
            const storageId = await ctx.storage.store(new Blob(['%PDF-']))
            const attachmentId = await ctx.db.insert('agentAttachments', {
                ...owner,
                storageId,
                name: 'a.pdf',
                kind: 'pdf',
                contentType: 'application/pdf',
                size: 5,
                expiresAt: Date.now() + ATTACHMENT_TTL_MS,
            })
            return { storageId, attachmentId }
        })
    return { t, as, store, seed }
}

describe('upload and register', () => {
    it('refuses everything while the flag is off', async () => {
        const { as, store } = await fixture({ enabled: false })
        const alice = as('alice')
        expect(
            await alice.mutation(
                api.v1.attachments.mutations.generateUploadUrl,
                {},
            ),
        ).toEqual({ ok: false, error: 'feature_disabled' })
        expect(
            await alice.mutation(api.v1.attachments.mutations.register, {
                storageId: await store(),
                name: 'resumen.pdf',
            }),
        ).toEqual({ ok: false, error: 'feature_disabled' })
    })

    it('hands a signed-in user an upload URL', async () => {
        const { as } = await fixture()
        expect(
            await as('alice').mutation(
                api.v1.attachments.mutations.generateUploadUrl,
                {},
            ),
        ).toMatchObject({ ok: true })
    })

    it('accepts a local account by uuid only', async () => {
        const { t } = await fixture()
        expect(
            await t.mutation(api.v1.attachments.mutations.generateUploadUrl, {
                deviceId: 'unknown',
            }),
        ).toEqual({ ok: false, error: 'unidentified_client' })
        expect(
            await t.mutation(api.v1.attachments.mutations.generateUploadUrl, {
                deviceId: DEVICE,
            }),
        ).toMatchObject({ ok: true })
    })

    it('never lets one stored file back two attachments', async () => {
        const { as, seed } = await fixture()
        const { storageId } = await seed({ userId: 'alice' })
        expect(
            await as('mallory').mutation(
                api.v1.attachments.mutations.register,
                { storageId, name: 'b.pdf' },
            ),
        ).toEqual({ ok: false, error: 'invalid_file' })
    })

    it('rejects a garbage id and a file of no accepted type', async () => {
        const { as, store } = await fixture()
        const alice = as('alice')
        expect(
            await alice.mutation(api.v1.attachments.mutations.register, {
                storageId: 'not-an-id',
                name: 'x.pdf',
            }),
        ).toEqual({ ok: false, error: 'invalid_file' })
        expect(
            await alice.mutation(api.v1.attachments.mutations.register, {
                storageId: await store(),
                name: 'x.pdf',
            }),
        ).toEqual({ ok: false, error: 'unsupported_type' })
    })
})

describe('beginRead', () => {
    it('hands the file to its owner', async () => {
        const { t, seed } = await fixture()
        const { storageId, attachmentId } = await seed({ userId: 'alice' })
        expect(
            await t.mutation(internal.attachments.internal.beginRead, {
                userId: 'alice',
                attachmentId,
            }),
        ).toEqual({
            ok: true,
            attachment: {
                storageId,
                name: 'a.pdf',
                kind: 'pdf',
                contentType: 'application/pdf',
            },
        })
    })

    it('answers not_found to anyone else, and for garbage ids', async () => {
        const { t, seed } = await fixture()
        const { attachmentId } = await seed({ userId: 'alice' })
        for (const caller of [{ userId: 'mallory' }, { deviceId: DEVICE }]) {
            expect(
                await t.mutation(internal.attachments.internal.beginRead, {
                    ...caller,
                    attachmentId,
                }),
            ).toEqual({ ok: false, code: 'not_found' })
        }
        expect(
            await t.mutation(internal.attachments.internal.beginRead, {
                userId: 'alice',
                attachmentId: 'nope',
            }),
        ).toEqual({ ok: false, code: 'not_found' })
    })

    it('lets a device read only its own attachments', async () => {
        const { t, seed } = await fixture()
        const { attachmentId } = await seed({ deviceId: DEVICE })
        expect(
            await t.mutation(internal.attachments.internal.beginRead, {
                deviceId: DEVICE,
                attachmentId,
            }),
        ).toMatchObject({ ok: true })
        expect(
            await t.mutation(internal.attachments.internal.beginRead, {
                deviceId: '0e1d2c3b-4a59-4687-9a8b-7c6d5e4f3a2b',
                attachmentId,
            }),
        ).toEqual({ ok: false, code: 'not_found' })
    })

    it('refuses while the flag is off', async () => {
        const { t, seed } = await fixture({ enabled: false })
        const { attachmentId } = await seed({ userId: 'alice' })
        expect(
            await t.mutation(internal.attachments.internal.beginRead, {
                userId: 'alice',
                attachmentId,
            }),
        ).toEqual({ ok: false, code: 'feature_disabled' })
    })

    it('stops at expiry, and the cleanup removes row and file', async () => {
        const { t, seed } = await fixture()
        const { storageId, attachmentId } = await seed({ userId: 'alice' })
        vi.advanceTimersByTime(ATTACHMENT_TTL_MS)
        expect(
            await t.mutation(internal.attachments.internal.beginRead, {
                userId: 'alice',
                attachmentId,
            }),
        ).toEqual({ ok: false, code: 'expired' })

        await t.mutation(internal.attachments.internal.deleteExpired, {
            limit: 10,
        })
        await t.run(async (ctx) => {
            expect(await ctx.db.query('agentAttachments').collect()).toEqual([])
            expect(await ctx.db.system.get('_storage', storageId)).toBeNull()
        })
    })

    it('keeps a live attachment out of the orphan sweep', async () => {
        const { t, seed, store } = await fixture()
        const { storageId } = await seed({ userId: 'alice' })
        const orphan = await store()
        vi.advanceTimersByTime(1000)
        await t.mutation(internal.feedback.internal.deleteOrphanAttachments, {
            olderThanMs: 0,
            limit: 10,
        })
        await t.run(async (ctx) => {
            expect(
                await ctx.db.system.get('_storage', storageId),
            ).not.toBeNull()
            expect(await ctx.db.system.get('_storage', orphan)).toBeNull()
        })
    })
})

describe('read', () => {
    it('refuses an empty question before spending anything', async () => {
        const { as } = await fixture()
        expect(
            await as('alice').action(api.v1.attachments.actions.read, {
                attachmentId: 'x',
                question: '   ',
            }),
        ).toMatchObject({ ok: false, code: 'question_invalid' })
    })

    it('forwards a gate refusal as a tool-ready error', async () => {
        const { as } = await fixture()
        expect(
            await as('alice').action(api.v1.attachments.actions.read, {
                attachmentId: 'missing',
                question: '¿Cuánto es el total?',
            }),
        ).toEqual({
            ok: false,
            code: 'not_found',
            error: 'Attachment not found',
        })
    })
})
