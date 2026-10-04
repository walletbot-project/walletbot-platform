import aggregate from '@convex-dev/aggregate/convex.config'
import betterAuth from '@convex-dev/better-auth/convex.config'
import migrations from '@convex-dev/migrations/convex.config.js'
import rateLimiter from '@convex-dev/rate-limiter/convex.config.js'
import resend from '@convex-dev/resend/convex.config'
import workflow from '@convex-dev/workflow/convex.config.js'
import { defineApp } from 'convex/server'

const app = defineApp()
app.use(betterAuth)
app.use(migrations)
app.use(rateLimiter)
app.use(resend)
// Materialising a recurring rule is a long fan-out of writes (up to 500
// occurrences), well past what one mutation should attempt. The workflow runs
// it in batches and resumes where it left off if a batch fails.
app.use(workflow)
// Outflows: signed effect on the source account
//   expense: -amount, income: +amount, transfer: -amount, balance_adjustment: +amount
app.use(aggregate, { name: 'outflowsByAccount' })
// Inflows: positive credit to the destination account for transfers
//   transfer: +toAmount, everything else: 0 (stored under '__none__' namespace)
app.use(aggregate, { name: 'inflowsByAccount' })
// One entry per (transaction, tag) join whose transaction is live, keyed by
// the transaction's date: a tag's count up to the occurrence cutoff is one
// O(log n) read instead of one document read per join.
app.use(aggregate, { name: 'transactionsByTag' })
// Raw operation durations for the p50/p95/p99 latency gauges
// (telemetry/latency.ts).
app.use(aggregate, { name: 'latencyByOperation' })

export default app
