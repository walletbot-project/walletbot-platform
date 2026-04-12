import type { api } from '@wallet-bot/backend/api'
import type { FunctionReturnType } from 'convex/server'

type ListResult = FunctionReturnType<
    typeof api.transactions.queries.listTransactions
>

export type Transaction = ListResult['page'][number]
