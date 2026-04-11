import { cronJobs } from 'convex/server'
import { internal } from './_generated/api'

const crons = cronJobs()

// Generate recurring transactions daily at 00:05 UTC
crons.cron(
    'generate recurring transactions',
    '5 0 * * *',
    internal.recurrences.internal.generateRecurringTransactions,
    {},
)

export default crons
