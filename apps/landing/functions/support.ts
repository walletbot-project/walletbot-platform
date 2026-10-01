import { localeRedirect } from '../src/lib/locale-redirect'

/**
 * Pages Function for `/support` (and `/support/`). See `functions/privacy.ts`.
 *
 * This is the URL handed to App Store Connect and Google Play as the app's
 * support link, so like the legal pages it has to negotiate a language rather
 * than 404.
 */
export const onRequest = localeRedirect('support')
