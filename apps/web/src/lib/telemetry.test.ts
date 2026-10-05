import { afterEach, describe, expect, it, vi } from 'vitest'
import {
    clientDurationBucket,
    createTelemetryClient,
    INSTALLATION_ID_KEY,
    type TelemetryClientOptions,
} from './telemetry'

const tick = () => new Promise((resolve) => setTimeout(resolve, 0))

function memoryStorage(initial: Record<string, string> = {}): Storage {
    const values = new Map(Object.entries(initial))
    return {
        get length() {
            return values.size
        },
        clear: () => values.clear(),
        getItem: (key) => values.get(key) ?? null,
        key: (index) => [...values.keys()][index] ?? null,
        removeItem: (key) => {
            values.delete(key)
        },
        setItem: (key, value) => {
            values.set(key, value)
        },
    }
}

function fixture(overrides: Partial<TelemetryClientOptions> = {}) {
    let ids = 0
    const fetch = vi.fn<typeof globalThis.fetch>(
        async () => new Response('{"ok":true}', { status: 200 }),
    )
    const storage = memoryStorage()
    const client = createTelemetryClient({
        siteUrl: 'https://site.test',
        appVersion: '0.5.1',
        fetch,
        storage: () => storage,
        newId: () => `id-${++ids}`,
        now: () => 1234,
        ...overrides,
    })
    const sent = () =>
        fetch.mock.calls.map(([url, init]) => ({
            url,
            init,
            body: JSON.parse(String(init?.body)),
        }))
    return { client, fetch, storage, sent }
}

const setupMetric = {
    name: 'voice.connect.setup_complete_bucket_count',
    type: 'counter',
    value: 1,
    unit: 'count',
    attributes: { bucket: '250-500', platform: 'web', resumed: false },
} as const

afterEach(() => vi.restoreAllMocks())

describe('clientDurationBucket', () => {
    it('uses the same boundaries as native', () => {
        expect(clientDurationBucket(0)).toBe('0-250')
        expect(clientDurationBucket(249)).toBe('0-250')
        expect(clientDurationBucket(250)).toBe('250-500')
        expect(clientDurationBucket(999)).toBe('500-1000')
        expect(clientDurationBucket(1000)).toBe('1000-2500')
        expect(clientDurationBucket(2500)).toBe('2500-5000')
        expect(clientDurationBucket(5000)).toBe('5000+')
    })
})

describe('createTelemetryClient', () => {
    it('posts one metric in the endpoint contract, anonymously without a token', async () => {
        const f = fixture()
        f.client.trackMetric(setupMetric)
        await tick()
        const [request] = f.sent()
        expect(request.url).toBe('https://site.test/telemetry/metrics')
        expect(request.init).toMatchObject({
            method: 'POST',
            keepalive: true,
            headers: { 'Content-Type': 'application/json' },
        })
        expect(request.init?.headers).not.toHaveProperty('Authorization')
        expect(request.body).toEqual({
            metrics: [
                {
                    ...setupMetric,
                    timestamp: 1234,
                    source: 'web',
                    installationId: 'id-2',
                    sessionId: f.client.sessionId,
                    appVersion: '0.5.1',
                    platform: 'web',
                },
            ],
        })
    })

    it('sends the bearer token only when one exists', async () => {
        const withToken = fixture({ getAccessToken: async () => 'jwt' })
        withToken.client.trackMetric(setupMetric)
        const withoutToken = fixture({ getAccessToken: async () => null })
        withoutToken.client.trackMetric(setupMetric)
        const failing = fixture({
            getAccessToken: async () => {
                throw new Error('offline')
            },
        })
        vi.spyOn(console, 'warn').mockImplementation(() => {})
        failing.client.trackMetric(setupMetric)
        await tick()
        expect(withToken.sent()[0].init?.headers).toMatchObject({
            Authorization: 'Bearer jwt',
        })
        expect(withoutToken.sent()[0].init?.headers).not.toHaveProperty(
            'Authorization',
        )
        expect(failing.sent()[0].init?.headers).not.toHaveProperty(
            'Authorization',
        )
    })

    it('keeps one installation id across sends and page loads, and one session id per client', async () => {
        const f = fixture()
        f.client.trackMetric(setupMetric)
        f.client.trackMetric(setupMetric)
        await tick()
        const [first, second] = f.sent()
        expect(first.body.metrics[0].installationId).toBe(
            second.body.metrics[0].installationId,
        )
        expect(f.storage.getItem(INSTALLATION_ID_KEY)).toBe(
            first.body.metrics[0].installationId,
        )

        const reloaded = createTelemetryClient({
            siteUrl: 'https://site.test',
            fetch: f.fetch,
            storage: () => f.storage,
            newId: () => 'fresh',
        })
        reloaded.trackMetric(setupMetric)
        await tick()
        const third = f.sent()[2]
        expect(third.body.metrics[0].installationId).toBe(
            first.body.metrics[0].installationId,
        )
        expect(third.body.metrics[0].sessionId).toBe('fresh')
        expect(third.body.metrics[0].sessionId).not.toBe(f.client.sessionId)
    })

    it('falls back to an in-memory installation id when storage throws', async () => {
        const f = fixture({
            storage: () => {
                throw new DOMException('Storage unavailable', 'SecurityError')
            },
        })
        f.client.trackMetric(setupMetric)
        f.client.trackMetric(setupMetric)
        await tick()
        const [first, second] = f.sent()
        expect(first.body.metrics[0].installationId).toBe('id-2')
        expect(second.body.metrics[0].installationId).toBe('id-2')
    })

    it('never throws: network and HTTP failures are only warned about', async () => {
        const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
        const rejected = fixture({
            fetch: vi.fn(async () => {
                throw new TypeError('Failed to fetch')
            }),
        })
        const refused = fixture({
            fetch: vi.fn(
                async () =>
                    new Response('{"code":"bad_request"}', { status: 400 }),
            ),
        })
        expect(() => rejected.client.trackMetric(setupMetric)).not.toThrow()
        expect(() => refused.client.trackMetric(setupMetric)).not.toThrow()
        await tick()
        expect(warn).toHaveBeenCalledWith(
            'telemetry metrics: send failed',
            expect.any(TypeError),
        )
        expect(warn).toHaveBeenCalledWith(
            'telemetry metrics: HTTP 400: {"code":"bad_request"}',
        )
    })

    it('sends nothing without a site URL', async () => {
        const f = fixture({ siteUrl: undefined })
        f.client.trackMetric(setupMetric)
        await tick()
        expect(f.fetch).not.toHaveBeenCalled()
    })
})
