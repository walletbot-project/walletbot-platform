import aggregate from '@convex-dev/aggregate/convex.config'
import betterAuth from '@convex-dev/better-auth/convex.config'
import resend from '@convex-dev/resend/convex.config'
import { defineApp } from 'convex/server'

const app = defineApp()
app.use(betterAuth)
app.use(resend)
// Outflows: signed effect on the source account
//   expense: -amount, income: +amount, transfer: -amount, balance_adjustment: +amount
app.use(aggregate, { name: 'outflowsByAccount' })
// Inflows: positive credit to the destination account for transfers
//   transfer: +toAmount, everything else: 0 (stored under '__none__' namespace)
app.use(aggregate, { name: 'inflowsByAccount' })

export default app
