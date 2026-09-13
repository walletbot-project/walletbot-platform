// "idOrName" resolution for the server-side agent.
//
// The tool contract lets the model pass either a UUID or the human name the
// user actually said ("mi cuenta del Galicia"). The UI never needs this — it
// navigates by id — so resolution lives with the agent.
//
// Mirrors the native resolver (`apps/native/lib/data/resolver.dart`) so the
// same sentence produces the same entity on both channels:
//
//   1. exact id match first, archived rows included — an id the model read
//      back from a previous tool result must keep working;
//   2. otherwise a normalized name match against *active* rows only;
//   3. several matches → ambiguous, with candidates for the model to ask
//      about, except for accounts where a unique match in the user's default
//      currency breaks the tie;
//   4. nothing → not found.
//
// Every query is narrowed by `userId` through an index, so the reads are
// bounded by one user's own entities.

import { normalizeName } from '@wallet-bot/shared'
import type { Doc } from '../_generated/dataModel'
import type { MutationCtx, QueryCtx } from '../_generated/server'
import { getDefaultCurrency } from '../v1/users/helpers'

type Ctx = QueryCtx | MutationCtx

export type Resolution<T> =
    | { kind: 'resolved'; value: T }
    | { kind: 'not_found' }
    | { kind: 'ambiguous'; candidates: { id: string; name: string }[] }

const decide = <T extends { id: string; name: string }>(
    matches: T[],
): Resolution<T> => {
    if (matches.length === 1) return { kind: 'resolved', value: matches[0] }
    if (matches.length > 1) {
        return {
            kind: 'ambiguous',
            candidates: matches.map((m) => ({ id: m.id, name: m.name })),
        }
    }
    return { kind: 'not_found' }
}

const nameMatches = (value: string, target: string): boolean =>
    normalizeName(value) === target

export const resolveAccount = async (
    ctx: Ctx,
    userId: string,
    idOrName: string,
): Promise<Resolution<Doc<'accounts'>>> => {
    const byId = await ctx.db
        .query('accounts')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', idOrName),
        )
        .unique()
    if (byId) return { kind: 'resolved', value: byId }

    const target = normalizeName(idOrName)
    const active = await ctx.db
        .query('accounts')
        .withIndex('by_user_archived', (q) =>
            q.eq('userId', userId).eq('isArchived', false),
        )
        .collect()
    const matches = active.filter((a) => nameMatches(a.name, target))

    if (matches.length > 1) {
        // "Efectivo" in ARS and "Efectivo" in USD is a normal setup, and the
        // user almost always means the one in their default currency. Only
        // fall through to asking when that doesn't disambiguate either.
        const defaultCurrency = await getDefaultCurrency(ctx, userId)
        const preferred = matches.filter((a) => a.currency === defaultCurrency)
        if (preferred.length === 1) {
            return { kind: 'resolved', value: preferred[0] }
        }
    }
    return decide(matches)
}

export const resolveCategory = async (
    ctx: Ctx,
    userId: string,
    idOrName: string,
): Promise<Resolution<Doc<'categories'>>> => {
    const byId = await ctx.db
        .query('categories')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', idOrName),
        )
        .unique()
    if (byId) return { kind: 'resolved', value: byId }

    const target = normalizeName(idOrName)
    const active = await ctx.db
        .query('categories')
        .withIndex('by_user_archived', (q) =>
            q.eq('userId', userId).eq('isArchived', false),
        )
        .collect()
    return decide(active.filter((c) => nameMatches(c.name, target)))
}

export const resolveTag = async (
    ctx: Ctx,
    userId: string,
    idOrName: string,
): Promise<Resolution<Doc<'tags'>>> => {
    const byId = await ctx.db
        .query('tags')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', idOrName),
        )
        .unique()
    if (byId) return { kind: 'resolved', value: byId }

    const target = normalizeName(idOrName)
    const active = await ctx.db
        .query('tags')
        .withIndex('by_user_archived', (q) =>
            q.eq('userId', userId).eq('isArchived', false),
        )
        .collect()
    return decide(active.filter((t) => nameMatches(t.name, target)))
}
