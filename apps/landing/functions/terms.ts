import { localeRedirect } from '../src/lib/locale-redirect'

/** Pages Function for `/terms` (and `/terms/`). See `functions/privacy.ts`. */
export const onRequest = localeRedirect('terms')
