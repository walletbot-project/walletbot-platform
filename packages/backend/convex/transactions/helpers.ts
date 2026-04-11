import type { Id } from '../_generated/dataModel'
import type { MutationCtx, QueryCtx } from '../_generated/server'

interface TransactionInput {
    type: 'expense' | 'income' | 'transfer'
    fromAccountId?: Id<'accounts'>
    toAccountId?: Id<'accounts'>
    categoryId?: Id<'categories'>
}

/**
 * Validate transaction fields based on type.
 */
export function validateTransactionShape(input: TransactionInput): void {
    switch (input.type) {
        case 'expense':
            if (!input.fromAccountId)
                throw new Error('Expense requires a source account')
            if (input.toAccountId)
                throw new Error('Expense should not have a destination account')
            break
        case 'income':
            if (!input.toAccountId)
                throw new Error('Income requires a destination account')
            if (input.fromAccountId)
                throw new Error('Income should not have a source account')
            break
        case 'transfer':
            if (!input.fromAccountId)
                throw new Error('Transfer requires a source account')
            if (!input.toAccountId)
                throw new Error('Transfer requires a destination account')
            if (input.fromAccountId === input.toAccountId)
                throw new Error(
                    'Transfer source and destination must be different',
                )
            if (input.categoryId)
                throw new Error('Transfers should not have a category')
            break
    }
}

/**
 * Compute the balance for a given account.
 * balance = sum(incoming) - sum(outgoing)
 */
export async function computeAccountBalance(
    ctx: QueryCtx | MutationCtx,
    userId: string,
    accountId: Id<'accounts'>,
): Promise<{ balanceCents: number; currency: string }> {
    const account = await ctx.db.get(accountId)
    if (!account) throw new Error('Account not found')
    if (account.userId !== userId) throw new Error('Not authorized')

    // Sum incoming (toAccountId = this account)
    // For cross-currency transfers, use destinationAmount (what actually arrived)
    let incoming = 0
    const inTxs = await ctx.db
        .query('transactions')
        .withIndex('by_userId_and_toAccountId', (q) =>
            q.eq('userId', userId).eq('toAccountId', accountId),
        )
        .take(5000)
    for (const tx of inTxs) {
        incoming += tx.destinationAmount ?? tx.amount
    }

    // Sum outgoing (fromAccountId = this account)
    // Source side always uses amount+currency (what actually left)
    let outgoing = 0
    const outTxs = await ctx.db
        .query('transactions')
        .withIndex('by_userId_and_fromAccountId', (q) =>
            q.eq('userId', userId).eq('fromAccountId', accountId),
        )
        .take(5000)
    for (const tx of outTxs) {
        outgoing += tx.amount
    }

    return {
        balanceCents: incoming - outgoing,
        currency: account.currency,
    }
}
