import { MINUTE, RateLimiter } from '@convex-dev/rate-limiter'
import { components } from '../_generated/api'

// better-auth's own rate limiter (`customRules` in auth.ts) only guards the
// routes IT serves. The native handlers call `auth.api.requestPasswordReset` /
// `auth.api.sendVerificationEmail` server-side, which never crosses that
// middleware — so without this, `/auth/password/forgot` and
// `/auth/email/resend-verification` are unbounded email-send amplifiers.
//
// Rates mirror the better-auth `customRules` (3 per minute) so both entry
// points to the same email behave the same way.
export const authRateLimiter = new RateLimiter(components.rateLimiter, {
    passwordResetEmail: { kind: 'fixed window', rate: 3, period: MINUTE },
    verificationEmail: { kind: 'fixed window', rate: 3, period: MINUTE },
})
