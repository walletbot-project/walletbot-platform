import { EMPTY_FILTER } from '@wallet-bot/shared'
import { describe, expect, it } from 'vitest'
import {
    readTransactionFormSeed,
    transactionFormSeedFromFilter,
} from './helpers'

describe('transactionFormSeedFromFilter', () => {
    it('prefills nothing from an empty filter', () => {
        expect(transactionFormSeedFromFilter(EMPTY_FILTER)).toEqual({
            type: undefined,
            accountId: undefined,
            destinationAccountId: undefined,
            categoryId: undefined,
        })
    })

    it('prefills a single type, account and category', () => {
        expect(
            transactionFormSeedFromFilter({
                ...EMPTY_FILTER,
                types: ['expense'],
                accountIds: ['acc'],
                categoryIds: ['cat'],
            }),
        ).toEqual({
            type: 'expense',
            accountId: 'acc',
            destinationAccountId: undefined,
            categoryId: 'cat',
        })
    })

    it('prefills nothing for a dimension with several values', () => {
        const seed = transactionFormSeedFromFilter({
            ...EMPTY_FILTER,
            types: ['expense', 'income'],
            accountIds: ['a', 'b'],
            categoryIds: ['x', 'y'],
        })
        expect(seed.type).toBeUndefined()
        expect(seed.accountId).toBeUndefined()
        expect(seed.categoryId).toBeUndefined()
    })

    it('leaves the type alone for a balance adjustment filter', () => {
        expect(
            transactionFormSeedFromFilter({
                ...EMPTY_FILTER,
                types: ['balance_adjustment'],
            }).type,
        ).toBeUndefined()
    })

    it('never gives a transfer a category', () => {
        const seed = transactionFormSeedFromFilter({
            ...EMPTY_FILTER,
            types: ['transfer'],
            categoryIds: ['cat'],
        })
        expect(seed.type).toBe('transfer')
        expect(seed.categoryId).toBeUndefined()
    })

    it('fills the transfer destination from a destination-side account', () => {
        const seed = transactionFormSeedFromFilter({
            ...EMPTY_FILTER,
            types: ['transfer'],
            accountIds: ['acc'],
            accountDirection: 'destination',
        })
        expect(seed.accountId).toBeUndefined()
        expect(seed.destinationAccountId).toBe('acc')
    })

    it('fills no account from a destination side without a transfer type', () => {
        const seed = transactionFormSeedFromFilter({
            ...EMPTY_FILTER,
            accountIds: ['acc'],
            accountDirection: 'destination',
        })
        expect(seed.accountId).toBeUndefined()
        expect(seed.destinationAccountId).toBeUndefined()
    })

    it('prefills nothing from an advanced filter', () => {
        expect(
            transactionFormSeedFromFilter({
                ...EMPTY_FILTER,
                types: ['expense'],
                advancedRoot: { combinator: 'or', children: [] },
            }),
        ).toEqual({})
    })
})

describe('readTransactionFormSeed', () => {
    it('reads the type and destination account it is handed', () => {
        expect(
            readTransactionFormSeed({
                type: 'transfer',
                destinationAccountId: 'acc',
            }),
        ).toMatchObject({ type: 'transfer', destinationAccountId: 'acc' })
    })

    it('drops a type the form cannot create', () => {
        expect(
            readTransactionFormSeed({ type: 'balance_adjustment' }).type,
        ).toBeUndefined()
    })
})
