import { internalMutation } from '../_generated/server'
import { todayDateString } from '../lib/validators'

/**
 * Generate transactions for all active recurrences that are due.
 * Called by the daily cron job.
 */
export const generateRecurringTransactions = internalMutation({
    args: {},
    handler: async (ctx) => {
        const today = todayDateString()

        const dueRecurrences = await ctx.db
            .query('recurrences')
            .withIndex('by_isActive_and_lastGeneratedDate', (q) =>
                q.eq('isActive', true).lt('lastGeneratedDate', today),
            )
            .take(100)

        // Also get recurrences that have never generated (lastGeneratedDate is undefined)
        const neverGenerated = await ctx.db
            .query('recurrences')
            .withIndex('by_isActive_and_lastGeneratedDate', (q) =>
                q.eq('isActive', true).eq('lastGeneratedDate', undefined),
            )
            .take(100)

        const allDue = [...dueRecurrences, ...neverGenerated]

        for (const recurrence of allDue) {
            // Check if past end date
            if (recurrence.endDate && recurrence.endDate < today) {
                await ctx.db.patch(recurrence._id, { isActive: false })
                continue
            }

            // Determine dates to generate for
            const lastDate =
                recurrence.lastGeneratedDate ?? recurrence.startDate
            const dates = getDatesBetween(
                lastDate,
                today,
                recurrence.frequency,
                recurrence.interval,
            )

            // Skip the lastDate itself, generate for all dates up to today
            for (const date of dates) {
                if (date <= lastDate) continue
                if (date > today) break
                if (recurrence.startDate > date) continue

                await ctx.db.insert('transactions', {
                    userId: recurrence.userId,
                    type: recurrence.type,
                    amount: recurrence.amount,
                    currency: recurrence.currency,
                    description: recurrence.description,
                    categoryId: recurrence.categoryId,
                    tags: recurrence.tags,
                    fromAccountId: recurrence.fromAccountId,
                    toAccountId: recurrence.toAccountId,
                    date,
                    notes: recurrence.notes,
                    recurrenceId: recurrence._id,
                })
            }

            await ctx.db.patch(recurrence._id, { lastGeneratedDate: today })
        }
    },
})

/**
 * Generate recurring dates between two dates based on frequency and interval.
 */
function getDatesBetween(
    startDate: string,
    endDate: string,
    frequency: 'daily' | 'weekly' | 'monthly' | 'yearly',
    interval: number,
): string[] {
    const dates: string[] = []
    const current = new Date(`${startDate}T00:00:00Z`)
    const end = new Date(`${endDate}T00:00:00Z`)

    // Safety: max 365 iterations
    let iterations = 0
    while (current <= end && iterations < 365) {
        dates.push(current.toISOString().slice(0, 10))

        switch (frequency) {
            case 'daily':
                current.setUTCDate(current.getUTCDate() + interval)
                break
            case 'weekly':
                current.setUTCDate(current.getUTCDate() + interval * 7)
                break
            case 'monthly':
                current.setUTCMonth(current.getUTCMonth() + interval)
                break
            case 'yearly':
                current.setUTCFullYear(current.getUTCFullYear() + interval)
                break
        }
        iterations++
    }

    return dates
}
