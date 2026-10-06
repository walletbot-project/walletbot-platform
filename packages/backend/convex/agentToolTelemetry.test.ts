// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { internal } from './_generated/api'
import { agentToolErrorOf } from './agent/helpers'
import schema from './schema'

const modules = import.meta.glob('./**/*.ts')
const now = Date.UTC(2026, 9, 3, 12, 0)
const userId = 'tool-telemetry-user'

function fixture() {
    const t = convexTest(schema, modules)
    aggregate.register(t, 'outflowsByAccount')
    aggregate.register(t, 'inflowsByAccount')
    aggregate.register(t, 'transactionsByTag')
    return t
}

const execute = (
    t: ReturnType<typeof fixture>,
    name: string,
    argsJson: string,
) =>
    t.mutation(internal.agent.tools.execute, {
        userId,
        name,
        argsJson,
        nowMs: now,
        utcOffsetMinutes: 0,
    })

async function toolMetrics(t: ReturnType<typeof fixture>) {
    return await t.run(async (ctx) =>
        (await ctx.db.query('telemetryMetrics').take(20)).map((m) => ({
            name: m.name,
            attributes: m.attributes,
        })),
    )
}

describe('agent tool telemetry', { timeout: 30000 }, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
    })
    afterEach(() => {
        vi.useRealTimers()
    })

    it('counts a call that returns, and its error when it failed', async () => {
        const t = fixture()
        const ok = JSON.parse(await execute(t, 'listAccounts', '{}'))
        expect(ok.ok).toBe(true)
        const failed = JSON.parse(
            await execute(t, 'getAccount', JSON.stringify({ idOrName: 'x' })),
        )
        expect(failed).toMatchObject({ ok: false })
        expect('reason' in failed).toBe(false)
        expect(await toolMetrics(t)).toEqual([
            {
                name: 'agent.tool.calls.count',
                attributes: { tool_name: 'listAccounts' },
            },
            {
                name: 'agent.tool.calls.count',
                attributes: { tool_name: 'getAccount' },
            },
            {
                name: 'agent.tool.errors.count',
                attributes: { tool_name: 'getAccount', reason: 'not_found' },
            },
        ])
    })

    it('throws malformed arguments as coded invalid_args, rolling back its telemetry', async () => {
        const t = fixture()
        for (const argsJson of ['{not json', JSON.stringify({ idOrName: 7 })]) {
            const error: unknown = await execute(
                t,
                'getAccount',
                argsJson,
            ).then(
                () => null,
                (thrown: unknown) => thrown,
            )
            expect(agentToolErrorOf(error)).toMatchObject({
                reason: 'invalid_args',
                message: expect.any(String),
            })
        }
        expect(await toolMetrics(t)).toEqual([])
    })

    it('records a thrown call and its reason from outside the rolled-back transaction', async () => {
        const t = fixture()
        await t.mutation(
            internal.telemetry.mutations.recordThrownAgentToolCall,
            {
                toolName: 'getAccount',
                reason: 'invalid_args',
            },
        )
        expect(await toolMetrics(t)).toEqual([
            {
                name: 'agent.tool.calls.count',
                attributes: { tool_name: 'getAccount' },
            },
            {
                name: 'agent.tool.errors.count',
                attributes: { tool_name: 'getAccount', reason: 'invalid_args' },
            },
        ])
    })
})
