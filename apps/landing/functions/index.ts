import { localeRedirect } from '../src/lib/locale-redirect'

/**
 * Pages Function for `/`, which has no prerendered content of its own.
 *
 * Pages' file-based routing maps `functions/index.ts` to exactly `/`, and
 * `public/_routes.json` pins invocation to the handful of unprefixed paths, so
 * the localized pages stay pure static assets and never spin up a Worker.
 */
export const onRequest = localeRedirect('')
