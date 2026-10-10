import { api } from '@wallet-bot/backend/api'
import {
    USABILITY_FIELDS,
    type UsabilityBlock,
    type UsabilityFieldValue,
    type UsabilityStep,
} from '@wallet-bot/shared'
import { useMutation, useQuery } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { useT } from '@/lib/i18n'

export type UsabilitySession = NonNullable<
    FunctionReturnType<typeof api.v1.usability.queries.get>
>

export type FieldValues = ReadonlyMap<string, UsabilityFieldValue>

export function useSessionFromUrl(): {
    session: UsabilitySession | null | undefined
    sessionId: string
} {
    const { sessionId = '' } = useParams()
    const session = useQuery(api.v1.usability.queries.get, { sessionId })
    return { session, sessionId }
}

export function participantCode(number: number): string {
    return `P${String(number).padStart(2, '0')}`
}

export function useFieldValues(session: UsabilitySession): FieldValues {
    return useMemo(
        () => new Map(session.fields.map((field) => [field.key, field.value])),
        [session.fields],
    )
}

export function numberValue(
    values: FieldValues,
    key: string,
): number | undefined {
    const value = values.get(key)
    return typeof value === 'number' ? value : undefined
}

/**
 * Field writes for one session. `save` applies optimistically to the open
 * `get` subscription, so typing never waits on the network; a failure rolls
 * back and says so. `stamp` waits for the server clock.
 */
export function useSessionWrites(sessionId: UsabilitySession['id']) {
    const t = useT()
    const setField = useMutation(
        api.v1.usability.mutations.setField,
    ).withOptimisticUpdate((store, args) => {
        const query = { sessionId: args.sessionId }
        const current = store.getQuery(api.v1.usability.queries.get, query)
        if (!current) return
        store.setQuery(api.v1.usability.queries.get, query, {
            ...current,
            fields: [
                ...current.fields.filter((field) => field.key !== args.key),
                { key: args.key, value: args.value },
            ],
        })
    })
    const stampField = useMutation(api.v1.usability.mutations.stampField)

    const save = useCallback(
        (key: string, value: UsabilityFieldValue) => {
            setField({ sessionId, key, value }).catch(() =>
                toast.error(t.usability.saveFailed),
            )
        },
        [setField, sessionId, t],
    )
    const stamp = useCallback(
        (key: string) => {
            stampField({ sessionId, key }).catch(() =>
                toast.error(t.usability.saveFailed),
            )
        },
        [stampField, sessionId, t],
    )
    return { save, stamp }
}

export function useNow(intervalMs: number): number {
    const [now, setNow] = useState(() => Date.now())
    useEffect(() => {
        const id = window.setInterval(() => setNow(Date.now()), intervalMs)
        return () => window.clearInterval(id)
    }, [intervalMs])
    return now
}

export function formatElapsed(ms: number): string {
    const total = Math.max(0, Math.floor(ms / 1000))
    const hours = Math.floor(total / 3600)
    const minutes = Math.floor((total % 3600) / 60)
    const seconds = total % 60
    const mm = String(minutes).padStart(2, '0')
    const ss = String(seconds).padStart(2, '0')
    return hours > 0 ? `${hours}:${mm}:${ss}` : `${mm}:${ss}`
}

export function formatClock(ms: number, locale: string): string {
    return new Date(ms).toLocaleTimeString(locale, {
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hourCycle: 'h23',
    })
}

function blockKeys(block: UsabilityBlock): string[] {
    switch (block.type) {
        case 'fields':
        case 'checklist':
            return block.fields.map((field) => field.key)
        case 'rows':
            return block.rows.flatMap((row) =>
                row.fields.map((field) => field.key),
            )
        case 'sus':
            return [...USABILITY_FIELDS.keys()].filter((key) =>
                key.startsWith('sus.'),
            )
        default:
            return []
    }
}

function isFilled(value: UsabilityFieldValue | undefined): boolean {
    if (value === undefined || value === null) return false
    if (typeof value === 'string') return value.trim().length > 0
    if (Array.isArray(value)) return value.length > 0
    return true
}

export function stepProgress(
    step: UsabilityStep,
    values: FieldValues,
): { done: number; total: number } {
    const keys = step.blocks.flatMap(blockKeys)
    return {
        done: keys.filter((key) => isFilled(values.get(key))).length,
        total: keys.length,
    }
}

export function filledText(value: UsabilityFieldValue | undefined): string {
    return typeof value === 'string' ? value.trim() : ''
}
