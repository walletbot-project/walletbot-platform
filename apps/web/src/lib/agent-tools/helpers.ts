import { api } from '@wallet-bot/backend/api'
import { normalizeName, TOOL_DEFINITIONS } from '@wallet-bot/shared'
import type { ConvexReactClient } from 'convex/react'
import type { z } from 'zod'

// Tool declarations (derived from shared)

export const agentToolDeclarations = TOOL_DEFINITIONS.map((d) => ({
    name: d.name,
    description: d.description,
    parameters: d.parameters,
}))

export type AgentToolContext = {
    client: ConvexReactClient
}

// Tool executors
// Each tool from shared MUST have an executor — adding a tool in
// shared without one here is a compile error (satisfies check).

export interface ToolExecutor {
    execute: (
        context: AgentToolContext,
        args: Record<string, unknown>,
    ) => Promise<Record<string, unknown>>
}

/** Bundle a Zod schema + typed handler into a validated executor. */
export function defineTool<T extends z.ZodType>(
    schema: T,
    handler: (
        context: AgentToolContext,
        args: z.infer<T>,
    ) => Promise<Record<string, unknown>>,
): ToolExecutor {
    return {
        execute: async (context, args) => {
            const parsed = schema.safeParse(args)
            if (!parsed.success) {
                return {
                    ok: false,
                    error: `Invalid args: ${parsed.error.message}`,
                }
            }
            try {
                return await handler(context, parsed.data)
            } catch (e) {
                return {
                    ok: false,
                    error: e instanceof Error ? e.message : String(e),
                }
            }
        },
    }
}

// ───── Name resolution ─────
//
// Tools accept `idOrName` strings. These helpers first try to load the entity
// by id; if that fails, they scan active entities and match by case-insensitive
// name. On ambiguity they return `{ ambiguous: true, candidates }` so the
// caller can surface that to the model.

export type Resolution<T> =
    | { ok: true; entity: T }
    | { ok: false; reason: 'not_found' }
    | {
          ok: false
          reason: 'ambiguous'
          candidates: { id: string; name: string }[]
      }

export async function resolveAccount(
    ctx: AgentToolContext,
    idOrName: string,
): Promise<Resolution<{ id: string; name: string; currency: string }>> {
    const byId = await ctx.client.query(api.v1.accounts.queries.get, {
        id: idOrName,
    })
    if (byId) return { ok: true, entity: byId }

    const list = await ctx.client.query(api.v1.accounts.queries.list, {
        includeArchived: false,
    })
    const target = normalizeName(idOrName)
    const matches = list.filter((a) => normalizeName(a.name) === target)
    if (matches.length === 1) return { ok: true, entity: matches[0] }
    if (matches.length === 0) return { ok: false, reason: 'not_found' }
    return {
        ok: false,
        reason: 'ambiguous',
        candidates: matches.map((m) => ({ id: m.id, name: m.name })),
    }
}

export async function resolveCategory(
    ctx: AgentToolContext,
    idOrName: string,
): Promise<Resolution<{ id: string; name: string }>> {
    const byId = await ctx.client.query(api.v1.categories.queries.get, {
        id: idOrName,
    })
    if (byId) return { ok: true, entity: byId }

    const list = await ctx.client.query(api.v1.categories.queries.listActive)
    const target = normalizeName(idOrName)
    const matches = list.filter((c) => normalizeName(c.name) === target)
    if (matches.length === 1) return { ok: true, entity: matches[0] }
    if (matches.length === 0) return { ok: false, reason: 'not_found' }
    return {
        ok: false,
        reason: 'ambiguous',
        candidates: matches.map((m) => ({ id: m.id, name: m.name })),
    }
}

export async function resolveTag(
    ctx: AgentToolContext,
    idOrName: string,
): Promise<Resolution<{ id: string; name: string }>> {
    const byId = await ctx.client.query(api.v1.tags.queries.get, {
        id: idOrName,
    })
    if (byId) return { ok: true, entity: byId }

    const list = await ctx.client.query(api.v1.tags.queries.listActive)
    const target = normalizeName(idOrName)
    const matches = list.filter((t) => normalizeName(t.name) === target)
    if (matches.length === 1) return { ok: true, entity: matches[0] }
    if (matches.length === 0) return { ok: false, reason: 'not_found' }
    return {
        ok: false,
        reason: 'ambiguous',
        candidates: matches.map((m) => ({ id: m.id, name: m.name })),
    }
}

/** Resolve many tag names/ids → ids. Silently drops unresolved (caller can re-check). */
export async function resolveTagIds(
    ctx: AgentToolContext,
    idsOrNames: string[],
): Promise<{ resolved: string[]; missing: string[] }> {
    const resolved: string[] = []
    const missing: string[] = []
    for (const item of idsOrNames) {
        const r = await resolveTag(ctx, item)
        if (r.ok) resolved.push(r.entity.id)
        else missing.push(item)
    }
    return { resolved, missing }
}

export function resolutionError(
    label: string,
    r: Extract<Resolution<unknown>, { ok: false }>,
): { ok: false; error: string; candidates?: { id: string; name: string }[] } {
    if (r.reason === 'not_found') {
        return { ok: false, error: `${label} not found` }
    }
    return {
        ok: false,
        error: `${label} is ambiguous`,
        candidates: r.candidates,
    }
}
