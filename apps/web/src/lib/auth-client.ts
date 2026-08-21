import {
    convexClient,
    crossDomainClient,
} from '@convex-dev/better-auth/client/plugins'
import { inferAdditionalFields } from 'better-auth/client/plugins'
import { createAuthClient } from 'better-auth/react'

export const authClient = createAuthClient({
    baseURL: import.meta.env.VITE_CONVEX_SITE_URL,
    plugins: [
        convexClient(),
        crossDomainClient(),
        // Mirrors the `user.additionalFields` entry in the server config
        // (packages/backend/convex/auth.ts) so sign-up can carry the accepted
        // legal-documents version.
        inferAdditionalFields({
            user: {
                termsAcceptedVersion: { type: 'string', required: false },
            },
        }),
    ],
})
