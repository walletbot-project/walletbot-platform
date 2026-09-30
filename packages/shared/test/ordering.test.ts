import { describe, expect, it } from 'vitest'
import { compareByPosition, type Orderable } from '../src/ordering'

function row(id: string, createdAt: bigint, position?: number) {
    return { id, createdAt, position }
}

function order(rows: (Orderable & { id: string })[]) {
    return [...rows].sort(compareByPosition).map((r) => r.id)
}

describe('compareByPosition', () => {
    it('falls back to creation order when nothing is positioned', () => {
        expect(order([row('b', 2n), row('c', 3n), row('a', 1n)])).toEqual([
            'a',
            'b',
            'c',
        ])
    })

    it('orders positioned rows by position', () => {
        expect(
            order([row('a', 1n, 2), row('b', 2n, 0), row('c', 3n, 1)]),
        ).toEqual(['b', 'c', 'a'])
    })

    it('puts unpositioned rows after positioned ones, by creation', () => {
        expect(
            order([
                row('new2', 9n),
                row('a', 1n, 1),
                row('new1', 5n),
                row('b', 2n, 0),
            ]),
        ).toEqual(['b', 'a', 'new1', 'new2'])
    })

    it('breaks position ties by creation', () => {
        expect(order([row('b', 2n, 0), row('a', 1n, 0)])).toEqual(['a', 'b'])
    })
})
