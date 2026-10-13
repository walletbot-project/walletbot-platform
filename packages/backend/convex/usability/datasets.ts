import {
    computeExchangeRate,
    mulberry32,
    recurrenceHorizon,
    type Scenario2Answers,
} from '@wallet-bot/shared'

export type CivilDay = { year: number; month: number; day: number }

export type PlanAccount = {
    key: string
    name: string
    currency: 'ARS' | 'USD'
    icon: string
    color: string
}

export type PlanCategory = {
    key: string
    name: string
    icon: string
    color: string
}

export type PlanTag = { key: string; name: string; color: string }

export type PlanRecurrence = { key: string; anchorMs: number; endMs?: number }

export type PlanTransaction = {
    type: 'expense' | 'income' | 'transfer' | 'balance_adjustment'
    name: string
    dateMs: number
    accountKey: string
    /** For a balance adjustment, the declared balance after it. */
    amountCents: number
    categoryKey?: string
    toAccountKey?: string
    toAmountCents?: number
    tagKeys?: string[]
    recurrence?: { key: string; index: number }
}

export type UsabilityPlan = {
    accounts: PlanAccount[]
    categories: PlanCategory[]
    tags: PlanTag[]
    recurrences: PlanRecurrence[]
    transactions: PlanTransaction[]
}

const DAY_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/

export function parseCivilDay(value: string): CivilDay | null {
    const match = DAY_PATTERN.exec(value)
    if (!match) return null
    const day = {
        year: Number(match[1]),
        month: Number(match[2]),
        day: Number(match[3]),
    }
    const check = new Date(Date.UTC(day.year, day.month - 1, day.day))
    if (
        check.getUTCFullYear() !== day.year ||
        check.getUTCMonth() !== day.month - 1 ||
        check.getUTCDate() !== day.day
    ) {
        return null
    }
    return day
}

export function formatCivilDay(day: CivilDay): string {
    const month = String(day.month).padStart(2, '0')
    const date = String(day.day).padStart(2, '0')
    return `${day.year}-${month}-${date}`
}

function addDays(day: CivilDay, days: number): CivilDay {
    const date = new Date(Date.UTC(day.year, day.month - 1, day.day + days))
    return {
        year: date.getUTCFullYear(),
        month: date.getUTCMonth() + 1,
        day: date.getUTCDate(),
    }
}

function daysInMonth(year: number, month: number): number {
    return new Date(Date.UTC(year, month, 0)).getUTCDate()
}

function shiftMonth(
    year: number,
    month: number,
    offset: number,
): { year: number; month: number } {
    const absolute = year * 12 + (month - 1) + offset
    return { year: Math.floor(absolute / 12), month: (absolute % 12) + 1 }
}

// Argentina has kept UTC-3 all year since 2009.
const ART_OFFSET_HOURS = 3

export function artMs(day: CivilDay, hour: number, minute: number): number {
    return Date.UTC(
        day.year,
        day.month - 1,
        day.day,
        hour + ART_OFFSET_HOURS,
        minute,
    )
}

/**
 * `occurrenceDateMs` from @wallet-bot/shared, monthly branch, on calendar days
 * instead of runtime-local time. Every series here is anchored at 00:05 in
 * Argentina (03:05 UTC), which is the same calendar day in both zones, so the
 * dates match what the server materialiser and the native app would compute.
 */
function monthlyOccurrence(anchor: CivilDay, index: number): CivilDay {
    const target = shiftMonth(anchor.year, anchor.month, index)
    const lastHere = daysInMonth(anchor.year, anchor.month)
    const lastThere = daysInMonth(target.year, target.month)
    const day =
        anchor.day === lastHere ? lastThere : Math.min(anchor.day, lastThere)
    return { ...target, day }
}

function dayNumber(day: CivilDay): number {
    return Date.UTC(day.year, day.month - 1, day.day) / 86_400_000
}

/**
 * The anchor in `month` whose fourth monthly occurrence lands closest to
 * `fourth`, later on a tie. Usually exact; near a month's end the last-day
 * rule can make the exact day unreachable.
 */
function closestAnchor(
    month: { year: number; month: number },
    fourth: CivilDay,
): CivilDay {
    let best: CivilDay = { ...month, day: 1 }
    let bestGap = Number.POSITIVE_INFINITY
    for (let day = 1; day <= daysInMonth(month.year, month.month); day += 1) {
        const candidate = { ...month, day }
        const gap =
            dayNumber(monthlyOccurrence(candidate, 3)) - dayNumber(fourth)
        if (
            Math.abs(gap) < Math.abs(bestGap) ||
            (Math.abs(gap) === Math.abs(bestGap) && gap > bestGap)
        ) {
            best = candidate
            bestGap = gap
        }
    }
    return best
}

const OPENING_BALANCE_NAME = 'Balance inicial'

function scenarioCategories(
    entries: [string, string, string, string][],
): PlanCategory[] {
    return entries.map(([key, name, icon, color]) => ({
        key,
        name,
        icon,
        color,
    }))
}

export function scenario0Plan(sessionDay: CivilDay): UsabilityPlan {
    const opening = addDays(sessionDay, -10)
    const accounts: PlanAccount[] = [
        {
            key: 'efectivo',
            name: 'Efectivo',
            currency: 'ARS',
            icon: 'cash',
            color: '#26A69A',
        },
        {
            key: 'mercadopago',
            name: 'MercadoPago',
            currency: 'ARS',
            icon: 'wallet',
            color: '#42A5F5',
        },
        {
            key: 'tarjeta',
            name: 'Tarjeta de crédito',
            currency: 'ARS',
            icon: 'card',
            color: '#AB47BC',
        },
    ]
    const balances: [string, number][] = [
        ['efectivo', 45_000],
        ['mercadopago', 380_000],
        ['tarjeta', -250_000],
    ]
    return {
        accounts,
        categories: scenarioCategories([
            ['supermercado', 'Supermercado', 'shopping_cart', '#10B981'],
            ['comida', 'Comida', 'restaurant', '#F97316'],
            ['transporte', 'Transporte', 'transport', '#0EA5E9'],
            ['salidas', 'Salidas', 'celebration', '#8B5CF6'],
            ['servicios', 'Servicios', 'receipt', '#F59E0B'],
            ['salud', 'Salud', 'health', '#EF4444'],
            ['ropa', 'Ropa', 'shopping_bag', '#EC4899'],
            ['hogar', 'Hogar', 'home', '#14B8A6'],
        ]),
        tags: [],
        recurrences: [],
        transactions: balances.map(([accountKey, pesos], index) => ({
            type: 'balance_adjustment',
            name: OPENING_BALANCE_NAME,
            dateMs: artMs(opening, 9, index),
            accountKey,
            amountCents: pesos * 100,
        })),
    }
}

const SEED = 20_261_005

const MP_TARGET_PESOS = 87_320
const USD_TARGET_CENTS = 260_000
const USD_GOAL_CENTS = 500_000
const SAVING_PESOS = 300_000
const SAVING_USD_CENTS = 20_000
const VISA_OPENING_DEBT_PESOS = 620_000
const CASH_OPENING_PESOS = 15_000
const CASH_FLOOR_PESOS = 5_000
const GALICIA_TARGET_PESOS = 420_000
const GALICIA_FLOOR_PESOS = 50_000
const LAST_MONTH_TARGET_PESOS = 1_780_000
const MONTH_FLOOR_PESOS = 1_600_000
const MONTH_CEILING_PESOS = 1_800_000
const MIN_FLEX_PESOS = 60_000

type MonthRef = { offset: number; year: number; month: number }

type OneOff = {
    offsetDays?: number
    monthOffset?: number
    day?: number
    name: string
    pesos: number
    accountKey: string
    categoryKey: string
    tagKeys?: string[]
}

const TABLE_MOVEMENTS: OneOff[] = [
    {
        monthOffset: -1,
        day: 12,
        name: 'Ferretería El Tornillo',
        pesos: 23_450,
        accountKey: 'efectivo',
        categoryKey: 'hogar',
    },
    {
        monthOffset: -1,
        day: 2,
        name: 'Coto',
        pesos: 85_400,
        accountKey: 'visa',
        categoryKey: 'supermercado',
    },
    {
        monthOffset: -1,
        day: 7,
        name: 'Día',
        pesos: 62_150,
        accountKey: 'mercadopago',
        categoryKey: 'supermercado',
    },
    {
        monthOffset: -1,
        day: 13,
        name: 'Coto',
        pesos: 98_700,
        accountKey: 'visa',
        categoryKey: 'supermercado',
    },
    {
        monthOffset: -1,
        day: 18,
        name: 'Verdulería',
        pesos: 41_300,
        accountKey: 'efectivo',
        categoryKey: 'supermercado',
    },
    {
        monthOffset: -1,
        day: 23,
        name: 'Carrefour',
        pesos: 73_950,
        accountKey: 'visa',
        categoryKey: 'supermercado',
    },
    {
        monthOffset: -1,
        day: 28,
        name: 'Día',
        pesos: 50_800,
        accountKey: 'mercadopago',
        categoryKey: 'supermercado',
    },
    {
        monthOffset: -1,
        day: 20,
        name: 'Dentista',
        pesos: 180_000,
        accountKey: 'visa',
        categoryKey: 'salud',
    },
    ...[-5, -4, -3, -2, -1].map(
        (monthOffset): OneOff => ({
            monthOffset,
            day: 8,
            name: 'Farmacia',
            pesos: 12_000,
            accountKey: 'efectivo',
            categoryKey: 'salud',
        }),
    ),
    {
        offsetDays: -80,
        name: 'Cine',
        pesos: 32_000,
        accountKey: 'mercadopago',
        categoryKey: 'salidas',
        tagKeys: ['martina'],
    },
    {
        offsetDays: -62,
        name: 'Bar',
        pesos: 45_500,
        accountKey: 'visa',
        categoryKey: 'salidas',
        tagKeys: ['martina'],
    },
    {
        offsetDays: -41,
        name: 'Pizzería',
        pesos: 28_000,
        accountKey: 'efectivo',
        categoryKey: 'salidas',
        tagKeys: ['martina'],
    },
    {
        offsetDays: -20,
        name: 'Recital',
        pesos: 51_000,
        accountKey: 'visa',
        categoryKey: 'salidas',
        tagKeys: ['martina'],
    },
    {
        offsetDays: -6,
        name: 'Cena',
        pesos: 30_000,
        accountKey: 'mercadopago',
        categoryKey: 'salidas',
        tagKeys: ['martina'],
    },
    {
        offsetDays: -130,
        name: 'Salida',
        pesos: 35_000,
        accountKey: 'visa',
        categoryKey: 'salidas',
        tagKeys: ['martina'],
    },
    {
        offsetDays: -35,
        name: 'Regalo de cumpleaños',
        pesos: 40_000,
        accountKey: 'mercadopago',
        categoryKey: 'regalos',
        tagKeys: ['martina'],
    },
    {
        offsetDays: -70,
        name: 'Bar',
        pesos: 27_000,
        accountKey: 'efectivo',
        categoryKey: 'salidas',
        tagKeys: ['facu'],
    },
    {
        offsetDays: -45,
        name: 'Asado',
        pesos: 38_000,
        accountKey: 'mercadopago',
        categoryKey: 'salidas',
        tagKeys: ['facu'],
    },
    {
        offsetDays: -15,
        name: 'Bowling',
        pesos: 22_500,
        accountKey: 'visa',
        categoryKey: 'salidas',
        tagKeys: ['facu'],
    },
]

const SERVICES: {
    name: string
    day: number
    pesos: number
    accountKey: string
}[] = [
    { name: 'Internet', day: 6, pesos: 18_000, accountKey: 'visa' },
    { name: 'Celular', day: 8, pesos: 12_000, accountKey: 'visa' },
    { name: 'Factura de luz', day: 12, pesos: 32_000, accountKey: 'galicia' },
    { name: 'Factura de gas', day: 14, pesos: 21_000, accountKey: 'galicia' },
    { name: 'Agua', day: 18, pesos: 9_000, accountKey: 'galicia' },
]

const FILLER_NAMES: Record<string, string[]> = {
    supermercado: ['Coto', 'Día', 'Carrefour', 'Jumbo', 'Verdulería', 'Disco'],
    comidaAfuera: [
        'Almuerzo',
        'Café',
        'Pizza',
        'Sushi',
        'Hamburguesas',
        'Empanadas',
        'Rappi',
        'PedidosYa',
    ],
    transporte: ['Uber', 'Taxi', 'SUBE', 'Nafta', 'Cabify', 'Estacionamiento'],
    ropa: ['Remera', 'Jean', 'Campera', 'Zapatillas', 'Medias'],
    salidas: ['Cine', 'Bar', 'Teatro', 'Recital', 'Boliche', 'Museo'],
}

const FILLER_ACCOUNTS: Record<string, string[]> = {
    supermercado: ['visa', 'visa', 'mercadopago', 'efectivo'],
    comidaAfuera: ['mercadopago', 'efectivo', 'visa'],
    transporte: ['mercadopago', 'efectivo', 'mercadopago'],
    ropa: ['visa'],
    salidas: ['mercadopago', 'efectivo', 'visa'],
}

const FLEX_WEIGHTS: [string, number, number][] = [
    ['comidaAfuera', 0.5, 11_000],
    ['transporte', 0.33, 6_000],
    ['ropa', 0.17, 25_000],
]

function clamp(value: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, value))
}

function roundTo(value: number, step: number): number {
    return Math.round(value / step) * step
}

/** Splits `total` pesos into `count` parts that add up to it exactly. */
function splitPesos(total: number, count: number, rng: () => number): number[] {
    if (count <= 1) return [total]
    const weights = Array.from({ length: count }, () => 0.6 + rng())
    const sum = weights.reduce((acc, weight) => acc + weight, 0)
    const parts = weights
        .slice(0, -1)
        .map((weight) => Math.max(50, roundTo((total * weight) / sum, 50)))
    const last = total - parts.reduce((acc, part) => acc + part, 0)
    if (last < 50) return splitPesos(total, count - 1, rng)
    return [...parts, last]
}

function pick<T>(items: readonly T[], rng: () => number): T {
    return items[Math.floor(rng() * items.length)]
}

export function scenario2Plan(sessionDay: CivilDay): {
    plan: UsabilityPlan
    answers: Scenario2Answers
} {
    const rng = mulberry32(SEED)
    const pastLimitMs = artMs(sessionDay, 6, 0)
    const isPast = (ms: number) => ms < pastLimitMs

    const months: MonthRef[] = [-5, -4, -3, -2, -1, 0].map((offset) => ({
        offset,
        ...shiftMonth(sessionDay.year, sessionDay.month, offset),
    }))
    const monthOf = (offset: number): MonthRef => months[offset + 5]
    const monthIndexOfMs = (ms: number): number | null => {
        const date = new Date(ms - ART_OFFSET_HOURS * 3_600_000)
        const year = date.getUTCFullYear()
        const month = date.getUTCMonth() + 1
        const found = months.find(
            (ref) => ref.year === year && ref.month === month,
        )
        return found ? found.offset : null
    }
    const daytime = (day: CivilDay) =>
        artMs(day, 9 + Math.floor(rng() * 13), Math.floor(rng() * 60))

    const accounts: PlanAccount[] = [
        {
            key: 'efectivo',
            name: 'Efectivo',
            currency: 'ARS',
            icon: 'cash',
            color: '#26A69A',
        },
        {
            key: 'mercadopago',
            name: 'MercadoPago',
            currency: 'ARS',
            icon: 'wallet',
            color: '#42A5F5',
        },
        {
            key: 'galicia',
            name: 'Galicia',
            currency: 'ARS',
            icon: 'bank',
            color: '#FF7043',
        },
        {
            key: 'visa',
            name: 'Visa',
            currency: 'ARS',
            icon: 'card',
            color: '#AB47BC',
        },
        {
            key: 'ahorro',
            name: 'Ahorro USD',
            currency: 'USD',
            icon: 'savings',
            color: '#84CC16',
        },
    ]
    const categories = scenarioCategories([
        ['supermercado', 'Supermercado', 'shopping_cart', '#10B981'],
        ['comidaAfuera', 'Comida afuera', 'restaurant', '#F97316'],
        ['salidas', 'Salidas', 'celebration', '#8B5CF6'],
        ['transporte', 'Transporte', 'transport', '#0EA5E9'],
        ['servicios', 'Servicios', 'receipt', '#F59E0B'],
        ['alquiler', 'Alquiler', 'home', '#78909C'],
        ['salud', 'Salud', 'health', '#EF4444'],
        ['ropa', 'Ropa', 'shopping_bag', '#EC4899'],
        ['suscripciones', 'Suscripciones', 'receipt', '#6366F1'],
        ['hogar', 'Hogar', 'home', '#14B8A6'],
        ['regalos', 'Regalos', 'celebration', '#D946EF'],
        ['sueldo', 'Sueldo', 'savings', '#84CC16'],
    ])
    const tags: PlanTag[] = [
        { key: 'martina', name: 'Martina', color: '#EC4899' },
        { key: 'facu', name: 'Facu', color: '#42A5F5' },
        { key: 'vacaciones', name: 'Vacaciones', color: '#FFCA28' },
        { key: 'trabajo', name: 'Trabajo', color: '#78909C' },
    ]

    const transactions: PlanTransaction[] = []
    const recurrences: PlanRecurrence[] = []

    const firstMonth = monthOf(-5)
    const openFrom: CivilDay = { ...firstMonth, day: 1 }
    const fridgeFourth = addDays(sessionDay, 5)
    const fridgeAnchorMonth = shiftMonth(
        fridgeFourth.year,
        fridgeFourth.month,
        -3,
    )
    const fridgeAnchor = closestAnchor(fridgeAnchorMonth, fridgeFourth)
    const openEnded = recurrenceHorizon('monthly').count
    const series: {
        key: string
        type: 'expense' | 'income'
        name: string
        anchor: CivilDay
        count: number
        pesos: number
        accountKey: string
        categoryKey: string
    }[] = [
        {
            key: 'sueldo',
            type: 'income',
            name: 'Sueldo',
            anchor: { ...openFrom, day: 1 },
            count: openEnded,
            pesos: 2_000_000,
            accountKey: 'galicia',
            categoryKey: 'sueldo',
        },
        {
            key: 'alquiler',
            type: 'expense',
            name: 'Alquiler',
            anchor: { ...openFrom, day: 5 },
            count: openEnded,
            pesos: 650_000,
            accountKey: 'galicia',
            categoryKey: 'alquiler',
        },
        {
            key: 'gimnasio',
            type: 'expense',
            name: 'Gimnasio',
            anchor: { ...openFrom, day: 10 },
            count: openEnded,
            pesos: 45_000,
            accountKey: 'mercadopago',
            categoryKey: 'suscripciones',
        },
        {
            key: 'netflix',
            type: 'expense',
            name: 'Netflix',
            anchor: { ...openFrom, day: 15 },
            count: openEnded,
            pesos: 12_000,
            accountKey: 'visa',
            categoryKey: 'suscripciones',
        },
        {
            key: 'heladera',
            type: 'expense',
            name: 'Heladera',
            anchor: fridgeAnchor,
            count: 6,
            pesos: 150_000,
            accountKey: 'visa',
            categoryKey: 'hogar',
        },
    ]
    const fridgeDates: CivilDay[] = []
    for (const rule of series) {
        const occurrences = Array.from({ length: rule.count }, (_, index) =>
            monthlyOccurrence(rule.anchor, index),
        )
        if (rule.key === 'heladera') fridgeDates.push(...occurrences)
        recurrences.push({
            key: rule.key,
            anchorMs: artMs(rule.anchor, 0, 5),
            endMs:
                rule.count === openEnded
                    ? undefined
                    : artMs(occurrences[occurrences.length - 1], 0, 5),
        })
        occurrences.forEach((day, index) => {
            transactions.push({
                type: rule.type,
                name: rule.name,
                dateMs: artMs(day, 0, 5),
                accountKey: rule.accountKey,
                amountCents: rule.pesos * 100,
                categoryKey: rule.categoryKey,
                recurrence: { key: rule.key, index },
            })
        })
    }

    for (const movement of TABLE_MOVEMENTS) {
        const day =
            movement.offsetDays !== undefined
                ? addDays(sessionDay, movement.offsetDays)
                : {
                      ...monthOf(movement.monthOffset ?? 0),
                      day: movement.day ?? 1,
                  }
        transactions.push({
            type: 'expense',
            name: movement.name,
            dateMs: daytime(day),
            accountKey: movement.accountKey,
            amountCents: movement.pesos * 100,
            categoryKey: movement.categoryKey,
            tagKeys: movement.tagKeys,
        })
    }

    const lastAllowedDay = (ref: MonthRef) =>
        ref.offset === 0 ? sessionDay.day - 1 : daysInMonth(ref.year, ref.month)
    const fraction = (ref: MonthRef) =>
        lastAllowedDay(ref) / daysInMonth(ref.year, ref.month)
    const randomDay = (ref: MonthRef): CivilDay => ({
        year: ref.year,
        month: ref.month,
        day: 1 + Math.floor(rng() * lastAllowedDay(ref)),
    })
    const pushFiller = (
        ref: MonthRef,
        categoryKey: string,
        totalPesos: number,
        count: number,
    ) => {
        if (totalPesos < 50 || count < 1 || lastAllowedDay(ref) < 1) return
        for (const pesos of splitPesos(totalPesos, count, rng)) {
            transactions.push({
                type: 'expense',
                name: pick(FILLER_NAMES[categoryKey], rng),
                dateMs: daytime(randomDay(ref)),
                accountKey: pick(FILLER_ACCOUNTS[categoryKey], rng),
                amountCents: pesos * 100,
                categoryKey,
            })
        }
    }

    for (const ref of months) {
        for (const service of SERVICES) {
            if (service.day > lastAllowedDay(ref)) continue
            const pesos = roundTo(service.pesos * (0.95 + rng() * 0.1), 10)
            transactions.push({
                type: 'expense',
                name: service.name,
                dateMs: daytime({ ...ref, day: service.day }),
                accountKey: service.accountKey,
                amountCents: pesos * 100,
                categoryKey: 'servicios',
            })
        }
        if (ref.offset === -1) continue
        const base =
            ref.offset === -2
                ? 412_300 * (0.97 + rng() * 0.06)
                : 400_000 + rng() * 40_000
        const budget = roundTo(base * fraction(ref), 10)
        const count =
            ref.offset === 0
                ? Math.max(1, Math.round(8 * fraction(ref)))
                : 7 + Math.floor(rng() * 3)
        pushFiller(ref, 'supermercado', budget, count)
    }

    const expenseCentsIn = (offset: number, categoryKey?: string) =>
        transactions
            .filter(
                (txn) =>
                    txn.type === 'expense' &&
                    isPast(txn.dateMs) &&
                    monthIndexOfMs(txn.dateMs) === offset &&
                    (categoryKey === undefined ||
                        txn.categoryKey === categoryKey),
            )
            .reduce((acc, txn) => acc + txn.amountCents, 0)

    const taggedOutings = (offset: number) =>
        expenseCentsIn(offset, 'salidas') / 100
    const comparedOutings =
        Math.max(70_000, taggedOutings(-2), taggedOutings(-1)) + 10_000
    for (const ref of months) {
        let target: number
        if (ref.offset === -2 || ref.offset === -1) {
            target = comparedOutings
        } else if (ref.offset === 0) {
            target = 80_000 * fraction(ref)
        } else {
            target = Math.max(
                taggedOutings(ref.offset) + 10_000,
                60_000 + rng() * 25_000,
            )
        }
        const untagged = roundTo(target - taggedOutings(ref.offset), 10)
        if (untagged < 5_000) continue
        pushFiller(
            ref,
            'salidas',
            untagged,
            clamp(Math.round(untagged / 18_000), 1, 5),
        )
    }

    const nonFlex = (offset: number) => expenseCentsIn(offset) / 100
    const lastFlexMax = MONTH_CEILING_PESOS - nonFlex(-1)
    const previousFlexMin = MONTH_FLOOR_PESOS - nonFlex(-2)
    let comparedFlex = LAST_MONTH_TARGET_PESOS - nonFlex(-1)
    if (comparedFlex < previousFlexMin) {
        comparedFlex = Math.min(previousFlexMin, lastFlexMax)
    }
    comparedFlex = Math.max(MIN_FLEX_PESOS, comparedFlex)
    for (const ref of months) {
        let flex: number
        if (ref.offset === -1) {
            flex = comparedFlex
        } else if (ref.offset === -2) {
            flex = comparedFlex * (0.97 + rng() * 0.06)
        } else if (ref.offset === 0) {
            flex = 150_000 * fraction(ref)
        } else {
            const target = 1_610_000 + rng() * 170_000
            flex = Math.max(MIN_FLEX_PESOS, target - nonFlex(ref.offset))
        }
        for (const [categoryKey, weight, average] of FLEX_WEIGHTS) {
            const budget = roundTo(flex * weight, 10)
            pushFiller(
                ref,
                categoryKey,
                budget,
                clamp(Math.round(budget / average), 1, 14),
            )
        }
    }

    const spendIn = (offset: number, accountKey: string) =>
        transactions
            .filter(
                (txn) =>
                    txn.type === 'expense' &&
                    txn.accountKey === accountKey &&
                    isPast(txn.dateMs) &&
                    monthIndexOfMs(txn.dateMs) === offset,
            )
            .reduce((acc, txn) => acc + txn.amountCents, 0) / 100
    const pushTransfer = (
        day: CivilDay,
        hour: number,
        name: string,
        fromKey: string,
        toKey: string,
        pesos: number,
        toAmountCents?: number,
    ) => {
        const dateMs = artMs(day, hour, 0)
        if (!isPast(dateMs) || pesos <= 0) return
        transactions.push({
            type: 'transfer',
            name,
            dateMs,
            accountKey: fromKey,
            amountCents: pesos * 100,
            toAccountKey: toKey,
            toAmountCents: toAmountCents ?? pesos * 100,
        })
    }
    for (const ref of months) {
        pushTransfer(
            { ...ref, day: 2 },
            10,
            'Ahorro',
            'galicia',
            'ahorro',
            SAVING_PESOS,
            SAVING_USD_CENTS,
        )
        pushTransfer(
            { ...ref, day: 1 },
            8,
            'Extracción',
            'galicia',
            'efectivo',
            Math.ceil(spendIn(ref.offset, 'efectivo') / 10_000) * 10_000,
        )
        pushTransfer(
            { ...ref, day: 1 },
            8,
            'Carga MercadoPago',
            'galicia',
            'mercadopago',
            Math.ceil(spendIn(ref.offset, 'mercadopago') / 10_000) * 10_000,
        )
        pushTransfer(
            { ...ref, day: 10 },
            11,
            'Pago resumen Visa',
            'galicia',
            'visa',
            ref.offset === -5
                ? VISA_OPENING_DEBT_PESOS
                : spendIn(ref.offset - 1, 'visa'),
        )
    }

    const pastMovements = transactions
        .filter(
            (txn) => isPast(txn.dateMs) && txn.type !== 'balance_adjustment',
        )
        .sort((a, b) => a.dateMs - b.dateMs)
    const netProfile = (accountKey: string) => {
        let net = 0
        let lowest = 0
        for (const txn of pastMovements) {
            if (txn.type === 'transfer') {
                if (txn.accountKey === accountKey) net -= txn.amountCents
                if (txn.toAccountKey === accountKey) {
                    net += txn.toAmountCents ?? txn.amountCents
                }
            } else if (txn.accountKey === accountKey) {
                net +=
                    txn.type === 'income' ? txn.amountCents : -txn.amountCents
            }
            lowest = Math.min(lowest, net)
        }
        return { net, lowest }
    }
    const netCents = (accountKey: string) => netProfile(accountKey).net
    const openingDay = addDays(openFrom, -1)
    const openingBalances: [string, number][] = [
        [
            'efectivo',
            Math.max(
                CASH_OPENING_PESOS * 100,
                CASH_FLOOR_PESOS * 100 - netProfile('efectivo').lowest,
            ),
        ],
        ['mercadopago', MP_TARGET_PESOS * 100 - netCents('mercadopago')],
        [
            'galicia',
            Math.max(
                GALICIA_TARGET_PESOS * 100 - netCents('galicia'),
                GALICIA_FLOOR_PESOS * 100 - netProfile('galicia').lowest,
            ),
        ],
        ['visa', -VISA_OPENING_DEBT_PESOS * 100],
        ['ahorro', USD_TARGET_CENTS - netCents('ahorro')],
    ]
    openingBalances.forEach(([accountKey, cents], index) => {
        transactions.push({
            type: 'balance_adjustment',
            name: OPENING_BALANCE_NAME,
            dateMs: artMs(openingDay, 9, index),
            accountKey,
            amountCents: cents,
        })
    })
    transactions.sort((a, b) => a.dateMs - b.dateMs)

    const balanceAt = (accountKey: string) => {
        const opening = openingBalances.find(([key]) => key === accountKey)
        return (opening?.[1] ?? 0) + netCents(accountKey)
    }
    const categoryName = (key: string) =>
        categories.find((category) => category.key === key)?.name ?? key
    const hardware = transactions.find(
        (txn) => txn.name === 'Ferretería El Tornillo',
    )
    const lastSupermarket = transactions.filter(
        (txn) =>
            txn.categoryKey === 'supermercado' &&
            monthIndexOfMs(txn.dateMs) === -1,
    )
    const threeMonthsAgo = artMs(addDays(sessionDay, -90), 0, 0)
    const martinaOutings = transactions.filter(
        (txn) =>
            txn.tagKeys?.includes('martina') &&
            txn.categoryKey === 'salidas' &&
            txn.dateMs >= threeMonthsAgo &&
            isPast(txn.dateMs),
    )
    const martinaTotal = martinaOutings.reduce(
        (acc, txn) => acc + txn.amountCents,
        0,
    )
    const centsOfTable = (name: string) =>
        (TABLE_MOVEMENTS.find((movement) => movement.name === name)?.pesos ??
            0) * 100
    const expenseCategories = categories.filter(
        (category) => category.key !== 'sueldo',
    )
    const savedCents = balanceAt('ahorro')

    return {
        plan: { accounts, categories, tags, recurrences, transactions },
        answers: {
            mercadoPagoBalanceCents: balanceAt('mercadopago'),
            hardware: {
                amountCents: hardware?.amountCents ?? 0,
                accountName:
                    accounts.find(
                        (account) => account.key === hardware?.accountKey,
                    )?.name ?? '',
                day: formatCivilDay({ ...monthOf(-1), day: 12 }),
            },
            supermarket: {
                totalCents: lastSupermarket.reduce(
                    (acc, txn) => acc + txn.amountCents,
                    0,
                ),
                count: lastSupermarket.length,
            },
            months: {
                previousMonth: `${monthOf(-2).year}-${String(monthOf(-2).month).padStart(2, '0')}`,
                lastMonth: `${monthOf(-1).year}-${String(monthOf(-1).month).padStart(2, '0')}`,
                previousTotalCents: expenseCentsIn(-2),
                lastTotalCents: expenseCentsIn(-1),
                categories: expenseCategories.map((category) => ({
                    name: categoryName(category.key),
                    previousCents: expenseCentsIn(-2, category.key),
                    lastCents: expenseCentsIn(-1, category.key),
                })),
            },
            martina: {
                totalCents: martinaTotal,
                count: martinaOutings.length,
                withGiftCents:
                    martinaTotal + centsOfTable('Regalo de cumpleaños'),
                withOldOutingCents: martinaTotal + centsOfTable('Salida'),
            },
            fridge: {
                paidCount: fridgeDates.filter((day) => isPast(artMs(day, 0, 5)))
                    .length,
                fourthDueDay: formatCivilDay(fridgeDates[3]),
            },
            savings: {
                currentUsdCents: savedCents,
                goalUsdCents: USD_GOAL_CENTS,
                monthlyUsdCents: SAVING_USD_CENTS,
                months: Math.ceil(
                    (USD_GOAL_CENTS - savedCents) / SAVING_USD_CENTS,
                ),
            },
        },
    }
}

export function exchangeRateFor(txn: PlanTransaction): number | undefined {
    if (txn.type !== 'transfer' || txn.toAmountCents === undefined) {
        return undefined
    }
    if (txn.toAmountCents === txn.amountCents) return undefined
    return computeExchangeRate(txn.amountCents, txn.toAmountCents)
}
