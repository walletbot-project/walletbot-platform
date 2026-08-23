import {
    convexClient,
    crossDomainClient,
} from '@convex-dev/better-auth/client/plugins'
import { createAuthClient } from 'better-auth/react'

// No `inferAdditionalFields`: the accepted legal-documents version is not a
// column on the user row. It travels in the body of our own sign-up endpoint,
// which records it against the `termsAcceptances` table (see
// packages/backend/convex/authNative/http.ts and lib/auth-signup.ts).
export const authClient = createAuthClient({
    baseURL: import.meta.env.VITE_CONVEX_SITE_URL,
    plugins: [convexClient(), crossDomainClient()],
})
