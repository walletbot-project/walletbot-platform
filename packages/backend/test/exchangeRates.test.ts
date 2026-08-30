// Unit tests for the exchange-rate provider adapters — outside convex/ so the
// Convex bundler never sees them. Everything under test is pure (no ctx, no
// fetch): the payloads below are trimmed copies of real provider responses.

import { describe, expect, it } from 'vitest'
import {
    parseDolarApi,
    parseFrankfurter,
    sourcePriority,
} from '../convex/exchangeRates/utils'

const DOLARES = [
    {
        moneda: 'USD',
        casa: 'oficial',
        nombre: 'Oficial',
        compra: 1480,
        venta: 1530,
        fechaActualizacion: '2026-08-24T18:00:00.000Z',
    },
    {
        moneda: 'USD',
        casa: 'blue',
        nombre: 'Blue',
        compra: 1545,
        venta: 1565,
        fechaActualizacion: '2026-08-24T21:00:00.000Z',
    },
    {
        moneda: 'USD',
        casa: 'tarjeta',
        nombre: 'Tarjeta',
        compra: 1924,
        venta: 1989,
        fechaActualizacion: '2026-08-24T18:00:00.000Z',
    },
]

describe('parseDolarApi', () => {
    it('maps each casa to its market and quotes the midpoint against ARS', () => {
        expect(parseDolarApi(DOLARES)).toEqual([
            {
                base: 'USD',
                quote: 'ARS',
                market: 'official',
                rate: 1505,
                buy: 1480,
                sell: 1530,
                asOf: Date.parse('2026-08-24T18:00:00.000Z'),
            },
            {
                base: 'USD',
                quote: 'ARS',
                market: 'blue',
                rate: 1555,
                buy: 1545,
                sell: 1565,
                asOf: Date.parse('2026-08-24T21:00:00.000Z'),
            },
            {
                base: 'USD',
                quote: 'ARS',
                market: 'card',
                rate: 1956.5,
                buy: 1924,
                sell: 1989,
                asOf: Date.parse('2026-08-24T18:00:00.000Z'),
            },
        ])
    })

    it('reads the other currencies endpoint the same way', () => {
        const parsed = parseDolarApi([
            {
                moneda: 'CLP',
                casa: 'oficial',
                compra: 1.6537,
                venta: 1.6537,
                fechaActualizacion: '2026-08-24T17:06:00.000Z',
            },
        ])
        expect(parsed).toHaveLength(1)
        expect(parsed[0].base).toBe('CLP')
        expect(parsed[0].quote).toBe('ARS')
        expect(parsed[0].rate).toBe(1.6537)
    })

    it('falls back to the side the provider published', () => {
        const parsed = parseDolarApi([
            {
                moneda: 'USD',
                casa: 'oficial',
                compra: 0,
                venta: 1530,
                fechaActualizacion: '2026-08-24T18:00:00.000Z',
            },
        ])
        expect(parsed[0].rate).toBe(1530)
        expect(parsed[0].buy).toBeUndefined()
    })

    it('drops rows it cannot trust instead of throwing', () => {
        expect(
            parseDolarApi([
                // Unknown casa.
                {
                    moneda: 'USD',
                    casa: 'futuro',
                    compra: 1,
                    venta: 2,
                    fechaActualizacion: '2026-08-24T18:00:00.000Z',
                },
                // Currency outside the app catalog.
                {
                    moneda: 'XBT',
                    casa: 'oficial',
                    compra: 1,
                    venta: 2,
                    fechaActualizacion: '2026-08-24T18:00:00.000Z',
                },
                // ARS quoted against itself.
                {
                    moneda: 'ARS',
                    casa: 'oficial',
                    compra: 1,
                    venta: 1,
                    fechaActualizacion: '2026-08-24T18:00:00.000Z',
                },
                // Unparseable timestamp.
                {
                    moneda: 'USD',
                    casa: 'blue',
                    compra: 1,
                    venta: 2,
                    fechaActualizacion: 'ayer',
                },
                // No usable price.
                {
                    moneda: 'USD',
                    casa: 'blue',
                    fechaActualizacion: '2026-08-24T18:00:00.000Z',
                },
                null,
                'nonsense',
            ]),
        ).toEqual([])
    })

    it('returns nothing for a non-array payload', () => {
        expect(parseDolarApi({ error: 'boom' })).toEqual([])
        expect(parseDolarApi(null)).toEqual([])
    })
})

describe('parseFrankfurter', () => {
    it('keeps catalog currencies and anchors the calendar day at UTC midnight', () => {
        expect(
            parseFrankfurter([
                { date: '2026-08-25', base: 'USD', quote: 'ARS', rate: 1499.3 },
                { date: '2026-08-24', base: 'USD', quote: 'BRL', rate: 5.1515 },
            ]),
        ).toEqual([
            {
                base: 'USD',
                quote: 'ARS',
                market: 'official',
                rate: 1499.3,
                asOf: Date.parse('2026-08-25T00:00:00.000Z'),
            },
            {
                base: 'USD',
                quote: 'BRL',
                market: 'official',
                rate: 5.1515,
                asOf: Date.parse('2026-08-24T00:00:00.000Z'),
            },
        ])
    })

    it('drops currencies the app does not know, self-pairs and bad rates', () => {
        expect(
            parseFrankfurter([
                { date: '2026-08-25', base: 'USD', quote: 'AFN', rate: 64.883 },
                { date: '2026-08-25', base: 'USD', quote: 'USD', rate: 1 },
                { date: '2026-08-25', base: 'USD', quote: 'EUR', rate: 0 },
                { date: 'someday', base: 'USD', quote: 'EUR', rate: 0.857 },
            ]),
        ).toEqual([])
    })
})

describe('sourcePriority', () => {
    it('ranks the Argentine provider above the reference-rate one', () => {
        expect(sourcePriority('dolarapi')).toBeGreaterThan(
            sourcePriority('frankfurter'),
        )
        expect(sourcePriority('whoever')).toBe(0)
    })
})
