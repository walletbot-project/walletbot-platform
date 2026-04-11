import { defineSchema } from 'convex/server'
import { expensesTables } from './schema/expenses'

export default defineSchema({
    ...expensesTables,
})
