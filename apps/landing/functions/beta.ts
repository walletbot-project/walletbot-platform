import { localeRedirect } from '../src/lib/locale-redirect'

/** Pages Function for `/beta` (and `/beta/`). See `functions/privacy.ts`. */
export const onRequest = localeRedirect('beta')
