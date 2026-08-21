import { type RequestContext, redirectToLocale } from '../src/i18n/negotiate'

/**
 * Pages Function for `/` — the site's root, which has no page in the build.
 *
 * Pages' file-based routing maps `functions/index.ts` to exactly `/`, and
 * `public/_routes.json` pins invocation to the unprefixed paths, so the
 * prerendered pages and every asset stay pure static requests and never spin up
 * a Worker. The `Accept-Language` negotiation lives in
 * `src/i18n/negotiate.ts`, shared with the other unprefixed routes.
 */
export function onRequest({ request }: RequestContext): Response {
    return redirectToLocale(request, '')
}
