// Shared helpers for the custom versioned HTTP API surface (`/v1/*`).
//
// CORS stays permissive for native clients, browser-based tooling, and future
// clients. These endpoints do not return per-origin secrets.

const CORS_HEADERS: Record<string, string> = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
}

export const jsonResponse = (body: unknown, init?: ResponseInit): Response => {
    const headers = new Headers(init?.headers)
    headers.set('Content-Type', 'application/json')
    for (const [key, value] of Object.entries(CORS_HEADERS)) {
        headers.set(key, value)
    }
    return new Response(JSON.stringify(body), { ...init, headers })
}

export const preflightResponse = (): Response =>
    new Response(null, { status: 204, headers: CORS_HEADERS })
