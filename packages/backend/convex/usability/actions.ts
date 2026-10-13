import { v } from 'convex/values'
import { internal } from '../_generated/api'
import { internalAction } from '../_generated/server'
import { createAuth } from '../auth'
import { usabilityScenarioValidator } from '../schema/usability'
import { testUserEmail, testUserName } from './utils'

/**
 * Creates one of a session's test users as a verified email+password account
 * with the current terms already accepted, so the phone goes straight from
 * sign-in to the app. Goes through better-auth's internal adapter rather than
 * `signUpEmail`, which would mail a verification link to an address nobody
 * reads.
 *
 * Idempotent: the address carries a per-session tag, so finding it already
 * registered means an earlier attempt of this same step got that far.
 */
export const createTestUser = internalAction({
    args: {
        sessionId: v.id('usabilitySessions'),
        scenario: usabilityScenarioValidator,
    },
    handler: async (ctx, { sessionId, scenario }): Promise<null> => {
        const session = await ctx.runQuery(
            internal.usability.internal.getSession,
            {
                sessionId,
            },
        )
        if (!session) throw new Error('Usability session not found')
        if (session.users.some((user) => user.scenario === scenario)) {
            return null
        }

        const email = testUserEmail(session.number, scenario, session.emailTag)
        const auth = createAuth(ctx, { acceptLanguage: 'es-AR' })
        const { internalAdapter, password } = await auth.$context
        const existing = await internalAdapter.findUserByEmail(email, {
            includeAccounts: true,
        })
        const user =
            existing?.user ??
            (await internalAdapter.createUser({
                email,
                name: testUserName(session.number, scenario),
                emailVerified: true,
            }))
        const hasPassword =
            existing?.accounts.some(
                (account) => account.providerId === 'credential',
            ) ?? false
        if (!hasPassword) {
            await internalAdapter.createAccount({
                userId: user.id,
                providerId: 'credential',
                accountId: user.id,
                password: await password.hash(session.password),
            })
        }

        await ctx.runMutation(
            internal.legal.internal.recordAcceptancesForUser,
            {
                userId: user.id,
                acceptance: {
                    documents: ['terms', 'privacy'],
                    ageConfirmed: true,
                    platform: 'backoffice',
                    locale: 'es',
                },
            },
        )
        await ctx.runMutation(internal.usability.internal.recordUser, {
            sessionId,
            scenario,
            userId: user.id,
            email,
        })
        return null
    },
})
